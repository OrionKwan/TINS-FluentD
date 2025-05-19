#!/bin/bash
# Script to set up SNMPv3 with NONE authentication and NONE privacy

# SNMPv3 Credentials - Using NONE for auth and privacy
SNMPV3_USER="NCEadmin"
AUTH_PROTOCOL="NONE"
AUTH_PASS=""
PRIV_PROTOCOL="NONE"
PRIV_PASS=""
CONTEXT_NAME=""

echo "=== Setting up SNMPv3 with NONE Authentication ==="
echo "Username: $SNMPV3_USER"
echo "Auth Protocol: $AUTH_PROTOCOL"
echo "Privacy Protocol: $PRIV_PROTOCOL"
echo "Context Name: ${CONTEXT_NAME:-<none>}"
echo

# Create a configuration file for the receiver
echo "Creating receiver configuration..."
cat > snmpv3-none.conf << EOF
# SNMPv3 configuration with NONE authentication and NONE privacy
createUser $SNMPV3_USER
authUser log,execute,net $SNMPV3_USER noauth
authCommunity log,execute,net public
disableAuthorization yes
traphandle default /usr/local/bin/format-trap.sh
EOF

# Also update the persistent configuration
echo "createUser $SNMPV3_USER" > persistent-snmpv3-none.conf

# Apply the configurations to the container
echo "Applying configuration to container..."
cat snmpv3-none.conf | docker exec -i fluentd-snmp-trap tee /etc/snmp/snmptrapd.conf > /dev/null
cat persistent-snmpv3-none.conf | docker exec -i fluentd-snmp-trap tee /var/lib/net-snmp/snmptrapd.conf > /dev/null
echo "Configuration applied."

# Create a test script for sending noAuth traps
echo "Creating test script..."
cat > test-snmpv3-none.sh << EOF
#!/bin/bash
# Test script for SNMPv3 with NONE authentication

# SNMPv3 Credentials
SNMPV3_USER="$SNMPV3_USER"
# No authentication or privacy parameters

# Generate unique test ID
TEST_ID="SNMPV3-NONE-\$(date +%s)"

echo "=== Testing SNMPv3 with NONE Authentication ==="
echo "Username: \$SNMPV3_USER"
echo "Auth Protocol: NONE"
echo "Privacy Protocol: NONE"
echo "Test ID: \$TEST_ID"
echo

echo "Sending SNMPv3 trap with NONE authentication..."
snmptrap -v 3 -u \$SNMPV3_USER -l noAuthNoPriv localhost:1162 '' \\
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "\$TEST_ID" 2>/dev/null

echo "Trap sent. Waiting for processing..."
sleep 2

echo "Checking if trap was received..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "\$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap with NONE auth was received!"
  echo "Log entry:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "\$TEST_ID"
else
  echo "❌ FAIL: SNMPv3 trap was not received."
  echo "Last 5 log entries:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5
fi

# Testing UDP forwarding
echo
echo "Testing direct UDP forwarding to 165.202.6.129:1237..."
echo "<snmp_trap><timestamp>\$(date)</timestamp><version>SNMPv3</version><user>\$SNMPV3_USER</user><auth>NONE</auth><id>\$TEST_ID-DIRECT</id></snmp_trap>" | nc -u 165.202.6.129 1237
echo "✅ Direct UDP message sent to 165.202.6.129:1237"
EOF

chmod +x test-snmpv3-none.sh

# Restart the container to apply configuration
echo "Restarting the container..."
docker-compose restart fluentd-snmp

echo 
echo "Setup complete. Run the test with:"
echo "./test-snmpv3-none.sh" 