#!/bin/bash
# Script to fix both the SNMPv3 authentication and Fluentd configuration issues

echo "===== Fixing SNMP and Fluentd Configuration ====="

# 1. Create a proper Fluentd configuration without the UDP plugin
echo "1. Creating updated Fluentd configuration..."
cat > /tmp/fixed-fluent.conf << EOF
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
    # Kafka Output
    @type kafka2
    @id out_kafka
    brokers "\#{ENV['KAFKA_BROKER'] || 'kafka:9092'}"
    topic "\#{ENV['KAFKA_TOPIC'] || 'snmp_traps'}"
    
    <format>
      @type json
    </format>
    
    <buffer tag,time>
      @type file
      path /fluentd/buffer/kafka
      flush_mode interval
      flush_interval 5s
      timekey 60
      timekey_wait 5s
      retry_type exponential_backoff
      retry_wait 1s
      retry_max_interval 60s
      retry_forever true
      chunk_limit_size 64m
    </buffer>
  </store>
  
  <store>
    # Debug output
    @type stdout
    <format>
      @type json
    </format>
  </store>
</match>

# Global error handling for all outputs
<label @ERROR>
  <match **>
    @type file
    @id out_error_file
    path /fluentd/log/error_%Y%m%d.log
    append true
    <format>
      @type json
    </format>
    <buffer time>
      @type file
      path /fluentd/buffer/error
      flush_mode interval
      flush_interval 5s
    </buffer>
  </match>
</label>

# Global log configuration
<system>
  log_level info
  log_path /fluentd/log/fluentd.log
</system>
EOF

# 2. Create updated SNMP trap configuration with SHA authentication
echo "2. Creating updated SNMP trap configuration..."
cat > /tmp/fixed-snmptrapd.conf << EOF
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

# 3. Start the container with updated configuration
echo "3. Restarting container with updated configuration..."
docker stop fluentd-snmp-trap
sleep 2

# Copy the updated configuration files to the container
docker cp /tmp/fixed-fluent.conf fluentd-snmp-trap:/fluentd/etc/fluent.conf
docker cp /tmp/fixed-snmptrapd.conf fluentd-snmp-trap:/etc/snmp/snmptrapd.conf

# Start the container
docker start fluentd-snmp-trap
sleep 5

# 4. Verify the container is running
echo "4. Verifying container status..."
if docker ps | grep -q fluentd-snmp-trap; then
  echo "SUCCESS: Container is running"
else
  echo "ERROR: Container is not running"
  docker logs fluentd-snmp-trap | tail -20
  exit 1
fi

# 5. Send a test trap
echo "5. Sending test trap with SHA authentication..."
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fluentd-snmp-trap)
TRAP_ID="TEST-SHA-$(date +%s)"

echo "Target: $CONTAINER_IP:1162"
snmptrap -v 3 -e 0x80001F88807C0F9A615F4B0768000000 -u NCEadmin -a SHA -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv "$CONTAINER_IP:1162" '' \
  1.3.6.1.4.1.2011.2.15.1.7.1.0.1 \
  1.3.6.1.4.1.2011.2.15.1.7.1.1.0 s "Test NE Name" \
  1.3.6.1.4.1.2011.2.15.1.7.1.2.0 s "Test NE Type" \
  1.3.6.1.4.1.2011.2.15.1.7.1.3.0 s "$TRAP_ID" 2>/dev/null

sleep 3

# 6. Check if trap was received
echo "6. Checking if trap was received..."
if docker exec fluentd-snmp-trap grep -q "$TRAP_ID" /var/log/snmptrapd.log; then
  echo "SUCCESS: Trap was received successfully!"
  docker exec fluentd-snmp-trap grep "$TRAP_ID" /var/log/snmptrapd.log
  
  # Check for MIB resolution
  if docker exec fluentd-snmp-trap grep -q "IMAP_NORTHBOUND_MIB" /var/log/snmptrapd.log || \
     docker exec fluentd-snmp-trap grep -q "HW-IMAPV1NORTHBOUND-TRAP-MIB" /var/log/snmptrapd.log; then
    echo "SUCCESS: MIB names are being resolved correctly!"
  else
    echo "WARNING: MIB names are not being resolved. Check MIB loading."
  fi
else
  echo "ERROR: Trap was not received or logged."
  echo "Recent log entries:"
  docker exec fluentd-snmp-trap tail -20 /var/log/snmptrapd.log
fi

# 7. Check overall container health
echo "7. Checking container health..."
echo "Log tail:"
docker logs fluentd-snmp-trap | tail -20

echo "===== Configuration Fix Complete ====="
rm -f /tmp/fixed-fluent.conf /tmp/fixed-snmptrapd.conf 