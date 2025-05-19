#!/bin/bash
# Script to fix permissions for SNMPv3 in the container

echo "=== Fixing SNMPv3 Permissions ==="

# Create needed directories
echo "Creating required directories..."
docker exec fluentd-snmp-trap mkdir -p /var/lib/snmp

# Fix permissions
echo "Setting permissions..."
docker exec fluentd-snmp-trap chmod -R 755 /var/lib/snmp
docker exec fluentd-snmp-trap chown -R root:root /var/lib/snmp

# Clean up any problematic files
echo "Cleaning up old configuration files..."
docker exec fluentd-snmp-trap rm -f /var/lib/snmp/snmpapp.conf
docker exec fluentd-snmp-trap rm -f /var/lib/net-snmp/snmptrapd.conf

# Create fresh configuration files
echo "Creating fresh SNMPv3 configuration..."
cat > snmpv3-fixed.conf << EOF
# SNMPv3 configuration for fluentd-snmp-trap
createUser NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
authUser log,execute,net NCEadmin authPriv
authCommunity log,execute,net public
disableAuthorization yes
traphandle default /usr/local/bin/format-trap.sh
EOF

# Apply configurations
echo "Applying configuration to container..."
cat snmpv3-fixed.conf | docker exec -i fluentd-snmp-trap tee /etc/snmp/snmptrapd.conf > /dev/null
cat snmpv3-fixed.conf | docker exec -i fluentd-snmp-trap tee /var/lib/net-snmp/snmptrapd.conf > /dev/null

# Restart the container to apply all changes
echo "Restarting the container..."
docker-compose restart fluentd-snmp

# Create test script
echo "Creating test script..."
cat > test-fixed-snmpv3.sh << 'EOF'
#!/bin/bash
# Test script for SNMPv3 with fixed permissions

# SNMPv3 Credentials
SNMPV3_USER="NCEadmin"
AUTH_PROTOCOL="MD5"
AUTH_PASS="P@ssw0rdauth"
PRIV_PROTOCOL="AES"
PRIV_PASS="P@ssw0rddata"

# Generate unique test ID
TEST_ID="FIXED-SNMPV3-$(date +%s)"

echo "=== Testing SNMPv3 with Fixed Permissions ==="
echo "Username: $SNMPV3_USER"
echo "Auth Protocol: $AUTH_PROTOCOL"
echo "Privacy Protocol: $PRIV_PROTOCOL"
echo "Test ID: $TEST_ID"
echo

echo "Sending SNMPv3 trap..."
snmptrap -v 3 -u $SNMPV3_USER \
  -a $AUTH_PROTOCOL -A $AUTH_PASS \
  -x $PRIV_PROTOCOL -X $PRIV_PASS \
  -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID" 2>/dev/null

echo "Trap sent. Waiting for processing..."
sleep 2

echo "Checking if trap was received..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap was received!"
  echo "Log entry:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID"
else
  echo "❌ FAIL: SNMPv3 trap was not received."
  echo "Last 5 log entries:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5
fi

# Also test direct UDP forwarding
echo
echo "Testing direct UDP forwarding to 165.202.6.129:1237..."
echo "<snmp_trap><timestamp>$(date)</timestamp><version>SNMPv3</version><user>$SNMPV3_USER</user><id>$TEST_ID-DIRECT</id></snmp_trap>" | nc -u 165.202.6.129 1237
echo "✅ Direct UDP message sent to 165.202.6.129:1237"
EOF

chmod +x test-fixed-snmpv3.sh

echo
echo "Permissions fixed. Run the test with:"
echo "./test-fixed-snmpv3.sh" 