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
