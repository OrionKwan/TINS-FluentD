#!/bin/bash
# Script to update SNMPv3 authentication and encryption settings in the container

echo "===== Updating SNMPv3 Authentication and Encryption Settings ====="

# 1. Start the container if not running
echo "1. Ensuring container is running..."
if ! docker ps | grep -q fluentd-snmp-trap; then
  echo "Starting container..."
  docker start fluentd-snmp-trap
  sleep 3
fi

# 2. Create updated snmptrapd.conf file
echo "2. Creating updated snmptrapd.conf with SHA authentication and AES encryption..."
cat > /tmp/updated-snmptrapd.conf << EOF
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

# 3. Copy the updated configuration to the container
echo "3. Copying updated configuration to container..."
docker cp /tmp/updated-snmptrapd.conf fluentd-snmp-trap:/etc/snmp/snmptrapd.conf

# 4. Also update the user configuration file
echo "4. Updating Net-SNMP users configuration..."
docker exec fluentd-snmp-trap sh -c "mkdir -p /var/lib/net-snmp"
docker exec fluentd-snmp-trap sh -c "echo 'createUser -e 0x80001F88807C0F9A615F4B0768000000 NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata' > /var/lib/net-snmp/snmptrapd.conf"
docker exec fluentd-snmp-trap sh -c "chmod 600 /var/lib/net-snmp/snmptrapd.conf"

# 5. Restart snmptrapd with new configuration
echo "5. Restarting snmptrapd with new configuration..."
docker exec fluentd-snmp-trap sh -c "killall snmptrapd 2>/dev/null || true"
sleep 1
docker exec fluentd-snmp-trap sh -c "snmptrapd -c /etc/snmp/snmptrapd.conf -Lf /var/log/snmptrapd.log -p /var/run/snmptrapd.pid -f &"
sleep 2

# 6. Verify snmptrapd is running
echo "6. Verifying snmptrapd is running..."
if docker exec fluentd-snmp-trap pgrep snmptrapd > /dev/null; then
  echo "SUCCESS: snmptrapd is running with updated configuration."
else
  echo "ERROR: snmptrapd failed to start. Please check logs."
  exit 1
fi

# 7. Send a test trap to verify the updated configuration
echo "7. Sending test trap to verify configuration..."
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fluentd-snmp-trap)
TRAP_ID="AUTH-UPDATE-TEST-$(date +%s)"

echo "Target: $CONTAINER_IP:1162"
snmptrap -v 3 -e 0x80001F88807C0F9A615F4B0768000000 -u NCEadmin -a SHA -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv "$CONTAINER_IP:1162" '' \
  1.3.6.1.6.3.1.1.5.1 \
  1.3.6.1.2.1.1.3.0 s "$TRAP_ID" 2>/dev/null

sleep 3

# 8. Check if trap was received
echo "8. Checking if trap was received..."
if docker exec fluentd-snmp-trap grep -q "$TRAP_ID" /var/log/snmptrapd.log; then
  echo "SUCCESS: Trap was received with new authentication and encryption settings!"
  docker exec fluentd-snmp-trap grep "$TRAP_ID" /var/log/snmptrapd.log
else
  echo "ERROR: Trap was not received. Configuration might not be correct."
  echo "Recent log entries:"
  docker exec fluentd-snmp-trap tail -20 /var/log/snmptrapd.log
fi

echo "===== Update Complete ====="
rm -f /tmp/updated-snmptrapd.conf 