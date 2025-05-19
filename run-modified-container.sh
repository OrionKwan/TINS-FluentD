#!/bin/bash
# Script to run a modified version of the fluentd-snmp container with SHA authentication

echo "===== Running Modified fluentd-snmp Container ====="

# Create configuration directory
mkdir -p ./modified-conf

# Create snmptrapd.conf with SHA authentication
cat > ./modified-conf/snmptrapd.conf << EOF
# SNMPv3 configuration
createUser -e 0x80001F88807C0F9A615F4B0768000000 NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata
authUser log,execute,net NCEadmin authPriv

# Accept SNMPv1/v2c traps with community string
authCommunity log,execute,net public

# Disable authorization to accept all traps
disableAuthorization yes

# Log format specification - more verbose
format1 TRAP: [%04y-%02m-%02d %02.2h:%02.2j:%02.2k] %B [%a] -> %b: %N::%W: %V
format2 TRAP: [%04y-%02m-%02d %02.2h:%02.2j:%02.2k] %B [%a] -> %b: %N::%W: %V
outputOption fts

# Log to file and stdout
logOption f,s /var/log/snmptrapd.log
EOF

# Create simplified fluent.conf without UDP plugin
cat > ./modified-conf/fluent.conf << EOF
# Read SNMP trap log file
<source>
  @type tail
  @id in_snmp_trap
  path /var/log/snmptrapd.log
  tag snmp.trap
  pos_file /tmp/snmptrapd.pos
  read_from_head true
  
  <parse>
    @type regexp
    expression /^(SNMPTRAP: |FORMATTED: )(?<message>.*)/
  </parse>
</source>

# Fan-out Stage - Main Output Pipeline
<match snmp.trap>
  @type copy
  
  <store>
    # Debug output
    @type stdout
    <format>
      @type json
    </format>
  </store>
</match>

# Global log configuration
<system>
  log_level info
  log_path /fluentd/log/fluentd.log
</system>
EOF

# Stop existing container if running
if docker ps -q -f name=fluentd-snmp-modified > /dev/null; then
  echo "Stopping existing container..."
  docker stop fluentd-snmp-modified
fi

# Remove existing container if it exists
if docker ps -a -q -f name=fluentd-snmp-modified > /dev/null; then
  echo "Removing existing container..."
  docker rm fluentd-snmp-modified
fi

# Run the modified container
echo "Starting modified fluentd-snmp container..."
docker run -d --name fluentd-snmp-modified \
  -p 1163:1162/udp \
  -v $(pwd)/fluentd-snmp/mibs:/fluentd/mibs \
  -v $(pwd)/modified-conf/snmptrapd.conf:/etc/snmp/snmptrapd.conf \
  -v $(pwd)/modified-conf/fluent.conf:/fluentd/etc/fluent.conf \
  -e SNMPV3_ENGINE_ID=0x80001F88807C0F9A615F4B0768000000 \
  fluentd-snmp-fixed

sleep 5

# Check if container is running
if docker ps -q -f name=fluentd-snmp-modified > /dev/null; then
  echo "Container started successfully!"
  
  # Get container IP
  CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fluentd-snmp-modified)
  echo "Container IP: $CONTAINER_IP"
  echo "SNMP Trap Port: 1163 (mapped to 1162 inside container)"
  
  # Send a test trap
  TRAP_ID="SHA-TEST-$(date +%s)"
  echo "Sending test trap with ID: $TRAP_ID"
  
  snmptrap -v 3 -e 0x80001F88807C0F9A615F4B0768000000 -u NCEadmin -a SHA -A P@ssw0rdauth \
    -x AES -X P@ssw0rddata -l authPriv localhost:1163 '' \
    1.3.6.1.4.1.2011.2.15.1.7.1.0.1 \
    1.3.6.1.4.1.2011.2.15.1.7.1.1.0 s "Test NE Name" \
    1.3.6.1.4.1.2011.2.15.1.7.1.2.0 s "Test NE Type" \
    1.3.6.1.4.1.2011.2.15.1.7.1.3.0 s "$TRAP_ID" 2>/dev/null
  
  sleep 3
  
  # Check if trap was received
  echo "Checking if trap was received..."
  if docker exec fluentd-snmp-modified grep -q "$TRAP_ID" /var/log/snmptrapd.log; then
    echo "SUCCESS: Trap was received successfully!"
    docker exec fluentd-snmp-modified grep "$TRAP_ID" /var/log/snmptrapd.log
    
    # Check for MIB names in the log
    if docker exec fluentd-snmp-modified grep -q "IMAP_NORTHBOUND_MIB" /var/log/snmptrapd.log || \
       docker exec fluentd-snmp-modified grep -q "HW-IMAPV1NORTHBOUND-TRAP-MIB" /var/log/snmptrapd.log; then
      echo "SUCCESS: MIB names are being resolved correctly!"
      echo "Your new MIB files are working with SHA authentication."
    else
      echo "WARNING: MIB names are not being resolved. The MIB files may not be loaded correctly."
    fi
  else
    echo "ERROR: Trap was not received or logged."
    echo "Recent log entries:"
    docker exec fluentd-snmp-modified tail -20 /var/log/snmptrapd.log
  fi
  
  echo "Container logs:"
  docker logs fluentd-snmp-modified | tail -20
else
  echo "ERROR: Container failed to start."
  echo "Logs:"
  docker logs fluentd-snmp-modified
fi

echo "===== Done =====" 