#!/bin/bash
# Script to convert a custom Engine ID and apply it to the container

# The numeric Engine ID we want to use
NUMERIC_ID="12345678911"

# Convert to hex (each digit becomes its ASCII hex value)
HEX_ID=""
for (( i=0; i<${#NUMERIC_ID}; i++ )); do
  CHAR="${NUMERIC_ID:$i:1}"
  ASCII_HEX=$(printf "%02x" "'$CHAR")
  HEX_ID="${HEX_ID}${ASCII_HEX}"
done

echo "Numeric Engine ID: $NUMERIC_ID"
echo "Hex representation: 0x$HEX_ID"

# Create configuration
CONFIG_FILE="engine-id-hex.conf"
cat > $CONFIG_FILE << EOF
# SNMPv3 configuration with custom Engine ID: $NUMERIC_ID
# Hex representation: 0x$HEX_ID
createUser -e 0x$HEX_ID NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata
authUser log,execute,net NCEadmin authPriv
authCommunity log,execute,net public
disableAuthorization yes
traphandle default /usr/local/bin/format-trap.sh
EOF

echo "Created configuration file: $CONFIG_FILE"

# Apply configuration to container
echo "Applying configuration to container..."
cat $CONFIG_FILE | docker exec -i fluentd-snmp-trap tee /etc/snmp/snmptrapd.conf > /dev/null
echo "Configuration applied to /etc/snmp/snmptrapd.conf"

# Update persistent configuration
echo "Updating persistent configuration..."
echo "createUser -e 0x$HEX_ID NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata" | \
  docker exec -i fluentd-snmp-trap tee /var/lib/net-snmp/snmptrapd.conf > /dev/null
echo "Persistent configuration updated in /var/lib/net-snmp/snmptrapd.conf"

# Restart container
echo "Restarting container..."
docker-compose restart fluentd-snmp
echo "Container restarted"

# Create test script
TEST_SCRIPT="test-hex-engine-id.sh"
cat > $TEST_SCRIPT << EOF
#!/bin/bash
# Test with hex Engine ID: 0x$HEX_ID (numeric: $NUMERIC_ID)

TEST_ID="HEX-ENGINE-\$(date +%s)"

echo "=== Testing SNMPv3 with Hex Engine ID ==="
echo "Numeric ID: $NUMERIC_ID"
echo "Hex ID: 0x$HEX_ID"
echo "Test ID: \$TEST_ID"
echo

echo "Sending SNMPv3 trap with hex Engine ID..."
snmptrap -v 3 -e 0x$HEX_ID -u NCEadmin -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \\
  -l authPriv localhost:1162 '' \\
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "\$TEST_ID" 2>/dev/null

echo "Trap sent. Waiting for processing..."
sleep 2

echo "Checking if trap was received..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "\$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap with hex Engine ID was received!"
  echo "Log entry:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "\$TEST_ID"
else
  echo "❌ FAIL: SNMPv3 trap was not received."
  echo "Last 5 log entries:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5
fi

echo
echo "Testing direct UDP forwarding to 165.202.6.129:1237..."
echo "<snmp_trap><timestamp>\$(date)</timestamp><engineID>$NUMERIC_ID</engineID><id>\$TEST_ID-DIRECT</id></snmp_trap>" | nc -u 165.202.6.129 1237
echo "✅ Direct UDP message sent to 165.202.6.129:1237"
EOF

chmod +x $TEST_SCRIPT
echo "Created test script: $TEST_SCRIPT"
echo "Run the test with: ./$TEST_SCRIPT" 