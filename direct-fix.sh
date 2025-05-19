#!/bin/bash
# Direct fix script for fluentd-snmp-trap container

echo "=== Direct Fix for fluentd-snmp-trap Container ==="

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

# Create a script to fix the container from inside
cat > fix-inside.sh << EOF
#!/bin/sh
# Create required directories
mkdir -p /var/lib/net-snmp /etc/snmp

# Copy config files
cat /tmp/snmptrapd-users.conf > /var/lib/net-snmp/snmptrapd.conf
cat /tmp/snmptrapd-fixed.conf > /etc/snmp/snmptrapd.conf

# Set permissions
chmod 600 /var/lib/net-snmp/snmptrapd.conf
chmod 644 /etc/snmp/snmptrapd.conf

# Report success
echo "Configuration files updated successfully"
EOF

# Make the script executable
chmod +x fix-inside.sh

# Start the container with modified volumes
echo "3. Starting container with updated configuration..."
docker run --rm -d --name fluentd-snmp-trap \
  -p 1162:1162/udp \
  -v $(pwd)/fluentd-snmp/conf:/fluentd/etc \
  -v $(pwd)/fluentd-snmp/plugins:/fluentd/plugins \
  -v $(pwd)/fluentd-snmp/mibs:/fluentd/mibs:ro \
  -v $(pwd)/snmptrapd-users.conf:/tmp/snmptrapd-users.conf \
  -v $(pwd)/snmptrapd-fixed.conf:/tmp/snmptrapd-fixed.conf \
  -v $(pwd)/fix-inside.sh:/tmp/fix-inside.sh \
  -e SNMPV3_USER=NCEadmin \
  -e SNMPV3_AUTH_PASS=P@ssw0rdauth \
  -e SNMPV3_PRIV_PASS=P@ssw0rddata \
  -e SNMPV3_AUTH_PROTOCOL=SHA \
  -e SNMPV3_PRIV_PROTOCOL=AES \
  -e KAFKA_BROKER=kafka:9092 \
  -e KAFKA_TOPIC=snmp_traps \
  -e UDP_FORWARD_HOST=165.202.6.129 \
  -e UDP_FORWARD_PORT=1237 \
  --network mvp-setup_opensearch-net \
  mvp-setup-fluentd-snmp

# Wait for container to start
echo "4. Waiting for container to start..."
sleep 5

# Run the fix script inside the container
echo "5. Running fix script inside container..."
docker exec fluentd-snmp-trap sh /tmp/fix-inside.sh

# Wait for configuration to apply
sleep 5

# Test trap reception
echo "6. Testing SNMPv3 trap reception..."
TEST_ID="DIRECT-FIXED-$(date +%s)"
docker exec fluentd-snmp-trap snmptrap -v 3 \
  -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID"

# Wait for processing
sleep 3

# Check if trap was received
echo "7. Checking if trap was received..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap was received by the container!"
  echo "Log entry:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID"
else
  echo "❌ FAIL: SNMPv3 trap was not received."
  echo "Last log entries:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5
fi

echo
echo "=== Fix completed ==="
echo "The fluentd-snmp-trap container should now be working with the correct Engine ID."
echo "Use the following command to send traps:"
echo "docker exec fluentd-snmp-trap snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s 'TEST-MESSAGE'" 