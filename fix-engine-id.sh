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
