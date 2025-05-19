#!/bin/bash
# Script to fix the original fluentd-snmp-trap container

echo "=== Fixing Original fluentd-snmp-trap Container ==="

# Stop the current container
echo "1. Stopping the container..."
docker stop fluentd-snmp-trap

# Define the correct Engine ID
ENGINE_ID="0x80001F88807C0F9A615F4B0768000000"
echo "Using Engine ID: $ENGINE_ID"

# Create temporary config files with correct Engine ID
echo "2. Creating configuration files with correct Engine ID..."

# Create SNMPv3 user file
echo "createUser -e $ENGINE_ID NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata" > snmptrapd-users.conf

# Create snmptrapd config
cat > snmptrapd-fixed.conf << EOF
# SNMPv3 configuration 
createUser -e $ENGINE_ID NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
authUser log,execute,net NCEadmin authPriv

# Accept SNMPv1/v2c traps with community string
authCommunity log,execute,net public

# Disable authorization to accept all traps
disableAuthorization yes

# Use formatter script for all incoming traps
traphandle default /usr/local/bin/format-trap.sh
EOF

# Start container in privileged mode temporarily to modify the file
echo "3. Starting container in privileged mode to fix configuration..."
docker run --rm -d --name temp-fix --privileged \
  --volumes-from fluentd-snmp-trap \
  alpine:latest sleep 30

# Copy files to the correct locations
echo "4. Copying configuration files to correct locations..."
docker cp snmptrapd-users.conf temp-fix:/var/lib/net-snmp/snmptrapd.conf
docker cp snmptrapd-fixed.conf temp-fix:/etc/snmp/snmptrapd.conf

# Ensure correct permissions
echo "5. Setting correct permissions..."
docker exec temp-fix chmod 600 /var/lib/net-snmp/snmptrapd.conf
docker exec temp-fix chmod 644 /etc/snmp/snmptrapd.conf

# Stop the temporary container
echo "6. Stopping temporary container..."
docker stop temp-fix

# Start the original container
echo "7. Starting original container with fixed configuration..."
docker start fluentd-snmp-trap

# Wait for container to start
echo "8. Waiting for container to start..."
sleep 10

# Verify the container is running
echo "9. Verifying container is running..."
docker ps | grep fluentd-snmp-trap

# Test trap reception
echo "10. Testing SNMPv3 trap reception..."
TEST_ID="FIXED-ORIGINAL-$(date +%s)"
docker exec fluentd-snmp-trap snmptrap -v 3 \
  -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID"

# Wait for processing
sleep 3

# Check if trap was received
echo "11. Checking if trap was received..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap was received by the original container!"
  echo "Log entry:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID"
else
  echo "❌ FAIL: SNMPv3 trap was not received."
  echo "Last log entries:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5
fi

echo
echo "=== Fix completed ==="
echo "The original fluentd-snmp-trap container should now be working with the correct Engine ID."
echo "Use the following command to send traps:"
echo "docker exec fluentd-snmp-trap snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s 'TEST-MESSAGE'" 