#!/bin/bash
# Test script sending the SNMP trap from inside the container

# SNMPv3 Credentials
SNMPV3_USER="NCEadmin"
AUTH_PROTOCOL="MD5"
AUTH_PASS="P@ssw0rdauth"
PRIV_PROTOCOL="AES"
PRIV_PASS="P@ssw0rddata"
ENGINE_ID="0x80001F88807C0F9A615F4B0768000000"

# Generate unique test ID
TEST_ID="CONTAINER-TEST-$(date +%s)"

echo "=== Testing SNMPv3 with Correct Engine ID from inside container ==="
echo "Username: $SNMPV3_USER"
echo "Auth Protocol: $AUTH_PROTOCOL"
echo "Privacy Protocol: $PRIV_PROTOCOL"
echo "Engine ID: $ENGINE_ID"
echo "Test ID: $TEST_ID"
echo

echo "Sending SNMPv3 trap from inside the container..."
docker exec fluentd-snmp-trap snmptrap -v 3 -e "$ENGINE_ID" -u "$SNMPV3_USER" \
  -a "$AUTH_PROTOCOL" -A "$AUTH_PASS" \
  -x "$PRIV_PROTOCOL" -X "$PRIV_PASS" \
  -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID"

echo "Trap sent. Waiting for processing..."
sleep 3

echo "Checking if trap was received by local trap daemon..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap with correct Engine ID was received!"
  echo "Log entry:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID"
else
  echo "❌ FAIL: SNMPv3 trap was not received by the local trap daemon."
  echo "Last 5 log entries:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5
fi

echo
echo "Test complete." 