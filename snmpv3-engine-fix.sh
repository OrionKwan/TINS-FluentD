#!/bin/bash
# Script to fix SNMPv3 by creating users with the correct Engine ID

echo "=== Fixing SNMPv3 Engine ID Mismatch ==="

# Create a script to run inside the container
cat > fix-engine-id.sh << 'EOF'
#!/bin/sh
set -e

# Create directories and fix permissions
mkdir -p /var/lib/snmp /var/lib/net-snmp
chmod -R 777 /var/lib/snmp /var/lib/net-snmp

# Clean any stale configs
rm -f /var/lib/snmp/snmpapp.conf /var/lib/net-snmp/snmptrapd.conf 2>/dev/null

# Start snmptrapd in debug mode to capture Engine ID
echo "Starting snmptrapd in debug mode to discover Engine ID..."
snmptrapd -Dusm,snmp -f -Lo -c /etc/snmp/snmptrapd.conf 0.0.0.0:1162 > /var/log/snmptrapd-debug.log 2>&1 &
sleep 2

# Send a test trap to generate Engine ID information
snmptrap -v 3 -u NCEadmin -l noAuthNoPriv localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "Engine-ID-Discovery"
sleep 1

# Kill the debug snmptrapd
pkill -f snmptrapd
sleep 1

# Extract the Engine ID from the debug log
ENGINE_ID=$(grep "engineID" /var/log/snmptrapd-debug.log | grep -o "80[0-9A-F: ]*" | head -1 | tr -d ' :')
if [ -z "$ENGINE_ID" ]; then
  echo "Failed to discover Engine ID. Using default SNMPv3 authentication."
  # Create generic configuration
  cat > /etc/snmp/snmptrapd.conf << CONF
createUser NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
authUser log,execute,net NCEadmin authPriv
authCommunity log,execute,net public
disableAuthorization yes
traphandle default /usr/local/bin/format-trap.sh
CONF
else
  echo "Discovered Engine ID: $ENGINE_ID"
  # Create configuration with the discovered Engine ID
  cat > /etc/snmp/snmptrapd.conf << CONF
# SNMPv3 configuration with discovered Engine ID
createUser -e 0x$ENGINE_ID NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
authUser log,execute,net -e 0x$ENGINE_ID NCEadmin authPriv
authUser log,execute,net NCEadmin authPriv
authCommunity log,execute,net public
disableAuthorization yes
traphandle default /usr/local/bin/format-trap.sh
CONF

  # Also update the persistent configuration
  echo "createUser -e 0x$ENGINE_ID NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata" > /var/lib/net-snmp/snmptrapd.conf
  chmod 600 /var/lib/net-snmp/snmptrapd.conf
fi

# Start snmptrapd with the new configuration
echo "Starting snmptrapd with fixed configuration..."
snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf 0.0.0.0:1162 &
sleep 2

# Test if SNMPv3 works with the new configuration
echo "Testing SNMPv3 configuration..."
TEST_ID="ENGINE-FIXED-$(date +%s)"

if [ -n "$ENGINE_ID" ]; then
  # Send a test trap with the discovered Engine ID
  echo "Sending test trap with Engine ID: 0x$ENGINE_ID"
  snmptrap -v 3 -e 0x$ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata \
    -l authPriv localhost:1162 '' \
    1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID"
fi

# Also try without Engine ID for comparison
echo "Sending test trap without Engine ID..."
snmptrap -v 3 -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "NO-ENGINE-ID-$TEST_ID"

sleep 2

# Check if the trap was received
echo "Checking if trap was logged..."
if grep -q "$TEST_ID" /var/log/snmptrapd.log; then
  echo "SUCCESS: SNMPv3 trap was received inside container!"
  grep "$TEST_ID" /var/log/snmptrapd.log
else
  echo "FAIL: SNMPv3 trap with Engine ID not found in log."
fi

if grep -q "NO-ENGINE-ID-$TEST_ID" /var/log/snmptrapd.log; then
  echo "SUCCESS: SNMPv3 trap without Engine ID was received!"
  grep "NO-ENGINE-ID-$TEST_ID" /var/log/snmptrapd.log
else
  echo "FAIL: SNMPv3 trap without Engine ID not found in log."
fi

# Output Engine ID for external use
if [ -n "$ENGINE_ID" ]; then
  echo "DISCOVERED_ENGINE_ID=0x$ENGINE_ID" > /tmp/engine_id.txt
  echo
  echo "========== IMPORTANT INFORMATION =========="
  echo "Engine ID: 0x$ENGINE_ID"
  echo "To send SNMPv3 traps from outside the container, use:"
  echo "snmptrap -v 3 -e 0x$ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata -l authPriv localhost:1162 ..."
  echo "=========================================="
fi
EOF

# Copy script to container and make executable
echo "Copying fix script to container..."
docker cp fix-engine-id.sh fluentd-snmp-trap:/fix-engine-id.sh
docker exec fluentd-snmp-trap chmod +x /fix-engine-id.sh

# Run the fix script inside the container
echo "Running Engine ID fix inside container..."
docker exec fluentd-snmp-trap /fix-engine-id.sh

# Get the discovered Engine ID for external use
echo "Getting Engine ID for external use..."
docker exec fluentd-snmp-trap cat /tmp/engine_id.txt > ./engine_id.txt || echo "No Engine ID file found."

if [ -f "./engine_id.txt" ]; then
  ENGINE_ID=$(grep "DISCOVERED_ENGINE_ID" ./engine_id.txt | cut -d= -f2)
  
  # Create a test script with the discovered Engine ID
  echo "Creating test script with the discovered Engine ID..."
  cat > test-with-correct-engine-id.sh << EOF
#!/bin/bash
# Test script with the correct Engine ID: $ENGINE_ID

# SNMPv3 Credentials
SNMPV3_USER="NCEadmin"
AUTH_PROTOCOL="MD5"
AUTH_PASS="P@ssw0rdauth"
PRIV_PROTOCOL="AES"
PRIV_PASS="P@ssw0rddata"
ENGINE_ID="$ENGINE_ID"

# Generate unique test ID
TEST_ID="CORRECT-ENGINE-\$(date +%s)"

echo "=== Testing SNMPv3 with Correct Engine ID ==="
echo "Username: \$SNMPV3_USER"
echo "Auth Protocol: \$AUTH_PROTOCOL"
echo "Privacy Protocol: \$PRIV_PROTOCOL"
echo "Engine ID: \$ENGINE_ID"
echo "Test ID: \$TEST_ID"
echo

echo "Sending SNMPv3 trap with correct Engine ID..."
snmptrap -v 3 -e \$ENGINE_ID -u \$SNMPV3_USER \\
  -a \$AUTH_PROTOCOL -A \$AUTH_PASS \\
  -x \$PRIV_PROTOCOL -X \$PRIV_PASS \\
  -l authPriv localhost:1162 '' \\
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "\$TEST_ID" 2>/dev/null

echo "Trap sent. Waiting for processing..."
sleep 2

echo "Checking if trap was received..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "\$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap with correct Engine ID was received!"
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
echo "<snmp_trap><timestamp>\$(date)</timestamp><version>SNMPv3</version><user>\$SNMPV3_USER</user><engineID>\$ENGINE_ID</engineID><id>\$TEST_ID-DIRECT</id></snmp_trap>" | nc -u 165.202.6.129 1237
echo "✅ Direct UDP message sent to 165.202.6.129:1237"
EOF
  chmod +x test-with-correct-engine-id.sh
  
  echo
  echo "Fix completed. Run the test with the correct Engine ID:"
  echo "./test-with-correct-engine-id.sh"
else
  echo
  echo "Engine ID could not be retrieved. SNMPv3 may still not work correctly."
fi 