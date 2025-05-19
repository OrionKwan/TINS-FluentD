#!/bin/bash
# Script to forward SNMP trap data from container's log to UDP destination

# Configuration
UDP_HOST="165.202.6.129"
UDP_PORT="1237"
TEST_ID="MANUAL-FORWARD-$(date +%s)"

echo "=== Manual Trap Forwarding Test ==="
echo "UDP Destination: $UDP_HOST:$UDP_PORT"
echo "Test ID: $TEST_ID"
echo

# Step 1: Send a trap to container
echo "1. Sending SNMPv3 trap to container..."
docker exec fluentd-snmp-fixed snmptrap -v 3 \
  -e 0x80001F88807C0F9A615F4B0768000000 \
  -u NCEadmin -a MD5 -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv \
  localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 \
  1.3.6.1.2.1.1.3.0 s "$TEST_ID"

# Wait for trap to be processed
echo "Waiting for trap processing..."
sleep 2

# Step 2: Verify the trap was received
echo "2. Verifying trap reception..."
if docker exec fluentd-snmp-fixed cat /var/log/snmptrapd.log | grep -q "$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap was received!"
  echo "Log entry:"
  TRAP_DATA=$(docker exec fluentd-snmp-fixed cat /var/log/snmptrapd.log | grep "FORMATTED" | grep "$TEST_ID" | head -1)
  echo "$TRAP_DATA"
else
  echo "❌ FAIL: SNMPv3 trap was not received."
  echo "Last 5 log entries:"
  docker exec fluentd-snmp-fixed cat /var/log/snmptrapd.log | tail -n 5
  exit 1
fi

# Step 3: Manually forward the trap data to UDP
echo
echo "3. Manually forwarding trap data to UDP destination $UDP_HOST:$UDP_PORT..."
XML_DATA="<snmp_trap><timestamp>$(date)</timestamp><version>SNMPv3</version><data>$TRAP_DATA</data></snmp_trap>"
echo "$XML_DATA" | nc -u $UDP_HOST $UDP_PORT
echo "✅ Trap data forwarded via UDP"

echo
echo "Test completed!"
echo "Check destination server logs at $UDP_HOST:$UDP_PORT for the trap data with ID: $TEST_ID" 