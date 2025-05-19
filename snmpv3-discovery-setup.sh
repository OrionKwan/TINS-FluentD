#!/bin/bash
# Script to set up SNMPv3 allowing Engine ID discovery

# SNMPv3 Credentials
SNMPV3_USER="NCEadmin"
AUTH_PROTOCOL="SHA"
AUTH_PASS="P@ssw0rdauth"
PRIV_PROTOCOL="AES"
PRIV_PASS="P@ssw0rddata"
CONTEXT_NAME=""  # Optional, leave blank if not needed

echo "=== Setting up SNMPv3 with Engine ID Discovery ==="
echo "Username: $SNMPV3_USER"
echo "Auth Protocol: $AUTH_PROTOCOL"
echo "Privacy Protocol: $PRIV_PROTOCOL"
echo "Context Name: ${CONTEXT_NAME:-<none>}"
echo

# Create a configuration file for the receiver without specifying Engine ID
echo "Creating receiver configuration..."
cat > snmpv3-discovery.conf << EOF
# SNMPv3 configuration allowing for Engine ID discovery
createUser $SNMPV3_USER $AUTH_PROTOCOL $AUTH_PASS $PRIV_PROTOCOL $PRIV_PASS
authUser log,execute,net $SNMPV3_USER authPriv
authCommunity log,execute,net public
disableAuthorization yes
traphandle default /usr/local/bin/format-trap.sh
EOF

# Apply the configuration to the container
echo "Applying configuration to container..."
cat snmpv3-discovery.conf | docker exec -i fluentd-snmp-trap tee /etc/snmp/snmptrapd.conf > /dev/null
echo "Configuration applied."

# Create a test script for sending traps without specifying Engine ID
echo "Creating test script..."
cat > test-snmpv3-discovery.sh << EOF
#!/bin/bash
# Test script for SNMPv3 with Engine ID discovery

# SNMPv3 Credentials
SNMPV3_USER="$SNMPV3_USER"
AUTH_PROTOCOL="$AUTH_PROTOCOL"
AUTH_PASS="$AUTH_PASS"
PRIV_PROTOCOL="$PRIV_PROTOCOL"
PRIV_PASS="$PRIV_PASS"
CONTEXT_NAME="$CONTEXT_NAME"

# Generate unique test ID
TEST_ID="SNMPV3-DISCOVERY-\$(date +%s)"

echo "=== Testing SNMPv3 with Engine ID Discovery ==="
echo "Username: \$SNMPV3_USER"
echo "Auth Protocol: \$AUTH_PROTOCOL"
echo "Privacy Protocol: \$PRIV_PROTOCOL"
echo "Test ID: \$TEST_ID"
echo

echo "Sending SNMPv3 trap without specifying Engine ID..."
# Note: No -e parameter to allow Engine ID discovery
snmptrap -v 3 -u \$SNMPV3_USER \\
  -a \$AUTH_PROTOCOL -A \$AUTH_PASS \\
  -x \$PRIV_PROTOCOL -X \$PRIV_PASS \\
  -l authPriv \\
  \${CONTEXT_NAME:+-n \$CONTEXT_NAME} \\
  localhost:1162 '' \\
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "\$TEST_ID" 2>/dev/null

echo "Trap sent. Waiting for processing..."
sleep 2

echo "Checking if trap was received..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "\$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap was received!"
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
echo "<snmp_trap><timestamp>\$(date)</timestamp><version>SNMPv3</version><user>\$SNMPV3_USER</user><id>\$TEST_ID-DIRECT</id></snmp_trap>" | nc -u 165.202.6.129 1237
echo "✅ Direct UDP message sent to 165.202.6.129:1237"
EOF

chmod +x test-snmpv3-discovery.sh

# Restart the container to apply configuration
echo "Restarting the container..."
docker-compose restart fluentd-snmp

echo 
echo "Setup complete. Run the test with:"
echo "./test-snmpv3-discovery.sh" 