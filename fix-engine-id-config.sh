#!/bin/bash
# Script to fix Engine ID configuration and restart the container

echo "=== Fixing Engine ID Configuration ==="

# Stop current container
echo "Stopping current container..."
docker stop fluentd-snmp-trap

# Get the Engine ID from test script for consistency
ENGINE_ID="0x80001F88807C0F9A615F4B0768000000"
echo "Using Engine ID: $ENGINE_ID"

# Create updated snmptrapd.conf for receiving traps
cat > new-snmptrapd.conf << EOF
# SNMPv3 configuration
createUser -e $ENGINE_ID NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
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

# Use format script (if exists)
traphandle default /usr/local/bin/format-trap.sh
EOF

# Create the persistent SNMPv3 user file
cat > snmp-users.conf << EOF
createUser -e $ENGINE_ID NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
EOF

# Create a simpler Fluentd config for direct UDP forwarding
cat > simpler-fluent.conf << EOF
# Read SNMP trap log file
<source>
  @type tail
  path /var/log/snmptrapd.log
  tag snmp.trap
  pos_file /tmp/snmptrapd.pos
  read_from_head true
  
  <parse>
    @type regexp
    expression /^(SNMPTRAP: |FORMATTED: )(?<message>.*)/
  </parse>
</source>

# Direct UDP forwarding for simplicity
<match snmp.trap>
  @type exec
  command echo "<snmp_trap><timestamp>\$(date)</timestamp><version>SNMPv3</version><data>%{message}</data></snmp_trap>" | nc -u 165.202.6.129 1237
  
  <buffer>
    @type memory
    flush_interval 1s
  </buffer>
  
  <format>
    @type single_value
    message_key message
  </format>
</match>

<system>
  log_level debug
</system>
EOF

# Create a basic test volume directory
mkdir -p tmp-config

# Copy configurations to temporary directory
cp new-snmptrapd.conf tmp-config/snmptrapd.conf
cp snmp-users.conf tmp-config/snmpusers.conf
cp simpler-fluent.conf tmp-config/fluent.conf

# Start container with volumes directly mounted to bypass read-only issues
echo "Starting container with updated configurations..."
docker run -d --name fluentd-snmp-fixed \
  -p 1162:1162/udp \
  --network="$(docker inspect -f '{{range $net,$v := .NetworkSettings.Networks}}{{$net}}{{end}}' fluentd-snmp-trap)" \
  -v "$(pwd)/tmp-config/snmptrapd.conf:/etc/snmp/snmptrapd.conf" \
  -v "$(pwd)/tmp-config/snmpusers.conf:/var/lib/net-snmp/snmptrapd.conf" \
  -v "$(pwd)/tmp-config/fluent.conf:/fluentd/etc/fluent.conf" \
  "$(docker inspect -f '{{.Config.Image}}' fluentd-snmp-trap)"

# Wait for container to start
echo "Waiting for container to start..."
sleep 5

# Test sending an SNMPv3 trap
echo "Testing SNMP trap reception..."
docker exec fluentd-snmp-fixed snmptrap -v 3 \
  -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "ENGINE-ID-FIX-TEST"

# Wait for processing
sleep 2

# Check if the trap was received
echo "Checking if trap was received..."
docker exec fluentd-snmp-fixed cat /var/log/snmptrapd.log | grep "ENGINE-ID-FIX-TEST"

echo "=== Engine ID configuration fix complete ==="
echo "To test SNMPv3 traps with the new container, use:"
echo "docker exec fluentd-snmp-fixed snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s 'TEST-MESSAGE'" 