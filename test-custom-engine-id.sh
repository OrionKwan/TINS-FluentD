#!/bin/bash
# Test script for custom Engine ID: 12345678911

# The custom Engine ID (represented in hex)
ENGINE_ID="0x3132333435363738393131"
TEST_ID="CUSTOM-ENGINE-$(date +%s)"

echo "=== Testing SNMPv3 with Custom Engine ID ==="
echo "Engine ID: 12345678911 (hex: $ENGINE_ID)"
echo "Test ID: $TEST_ID"
echo

echo "Sending SNMPv3 trap with custom Engine ID..."
snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID" 2>/dev/null

echo "Trap sent. Waiting for processing..."
sleep 2

echo "Checking if trap was received..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap with custom Engine ID was received!"
  echo "Log entry:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID"
else
  echo "❌ FAIL: SNMPv3 trap was not received."
  echo "Last 5 log entries:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5
fi

echo
echo "Testing direct UDP forwarding to 165.202.6.129:1237..."
echo "<snmp_trap><timestamp>$(date)</timestamp><engineID>12345678911</engineID><id>$TEST_ID-DIRECT</id></snmp_trap>" | nc -u 165.202.6.129 1237
echo "✅ Direct UDP message sent to 165.202.6.129:1237" 