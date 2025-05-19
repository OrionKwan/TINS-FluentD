#!/bin/bash

# Stop any existing container
docker stop fluentd-snmp-trap 2>/dev/null || true
docker rm fluentd-snmp-trap 2>/dev/null || true

# Start a basic container with net-snmp tools
docker run -d --name fluentd-snmp-trap \
  -p 1162:1162/udp \
  --network mvp-setup_opensearch-net \
  alpine:latest \
  tail -f /dev/null

# Install net-snmp
docker exec fluentd-snmp-trap apk add --no-cache net-snmp net-snmp-tools

# Copy snmptrapd configuration
cat > snmptrapd.conf.minimal << EOF
# SNMPv3 configuration
createUser -e 0x80001F88807C0F9A615F4B0768000000 NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
authUser log,execute,net NCEadmin authPriv
disableAuthorization yes
EOF

# Copy to container
docker cp snmptrapd.conf.minimal fluentd-snmp-trap:/etc/snmp/snmptrapd.conf

# Create log file
docker exec fluentd-snmp-trap sh -c "mkdir -p /var/log && touch /var/log/snmptrapd.log && chmod 666 /var/log/snmptrapd.log"

# Start snmptrapd in debug mode on the right port (explicitly 1162)
docker exec -d fluentd-snmp-trap sh -c "snmptrapd -c /etc/snmp/snmptrapd.conf -Lf /var/log/snmptrapd.log -p 1162 -f -Dusm,secmod -Le"

# Wait for it to start
sleep 2

# Display status and port binding
echo "Container running. Status:"
docker exec fluentd-snmp-trap ps -ef | grep snmptrapd
echo "Port binding:"
docker exec fluentd-snmp-trap netstat -lun | grep 1162

# Test sending a trap
echo "Sending test SNMPv3 trap..."
snmptrap -v 3 -e 0x80001F88807C0F9A615F4B0768000000 -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "TEST-TRAP-$(date +%s)" 2>/dev/null

sleep 2

# Check if trap was received
echo "Checking if trap was received..."
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -5 