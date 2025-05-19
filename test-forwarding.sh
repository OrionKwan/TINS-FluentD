#!/bin/bash
# Test script for SNMPv3 reception and UDP forwarding

# Get container IP address
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fluentd-snmp-trap)

# Generate unique test ID
TEST_ID="FULL-TEST-$(date +%s)"

echo "=== Testing SNMPv3 Reception and Forwarding ==="
echo "Test ID: $TEST_ID"
echo "Container IP: $CONTAINER_IP"
echo

# Step 1: Test direct UDP forwarding
echo "1. Testing direct UDP forwarding to 165.202.6.129:1237..."
echo "<snmp_trap><timestamp>$(date)</timestamp><version>SNMPv3</version><id>$TEST_ID-DIRECT-UDP</id></snmp_trap>" | nc -u 165.202.6.129 1237
echo "✅ Direct UDP message sent"
echo

# Step 2: Test SNMPv3 trap reception using the container-based test
echo "2. Testing SNMPv3 trap reception inside container..."
docker exec fluentd-snmp-trap snmptrap -v 3 \
  -e 0x80001F88807C0F9A615F4B0768000000 \
  -u NCEadmin -a MD5 -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv \
  localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 \
  1.3.6.1.2.1.1.3.0 s "$TEST_ID-SNMPV3-TRAP"

echo "Waiting for processing..."
sleep 3

# Step 3: Check if the SNMPv3 trap was received
echo "3. Checking if trap was received..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$TEST_ID-SNMPV3-TRAP"; then
  echo "✅ SUCCESS: SNMPv3 trap was received!"
  echo "Log entries:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID-SNMPV3-TRAP"
else
  echo "❌ FAIL: SNMPv3 trap was not received."
  echo "Last 5 log entries:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5
fi
echo

# Step 4: Manual UDP forwarding of the trap data
echo "4. Manually forwarding trap data via UDP..."
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID-SNMPV3-TRAP" | while read line; do
  echo "<snmp_trap><timestamp>$(date)</timestamp><version>SNMPv3</version><data>$line</data></snmp_trap>" | nc -u 165.202.6.129 1237
  echo "✅ Trap data forwarded via UDP"
done

echo
echo "Test completed!"
echo "Check destination server logs at 165.202.6.129:1237 for:"
echo "1. $TEST_ID-DIRECT-UDP (direct UDP test)"
echo "2. $TEST_ID-SNMPV3-TRAP (SNMPv3 trap forwarded via UDP)" 