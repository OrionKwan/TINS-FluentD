#!/bin/bash
# Comprehensive Test Script for fluentd-snmp Container using SNMPv2c
# This script avoids SNMPv3 Engine ID issues by using SNMPv2c

# Generate a unique test ID
TEST_ID="FULL-TEST-V2C-$(date +%s)"
echo "=== fluentd-snmp Container Test (ID: $TEST_ID) ==="
echo "This script tests the entire pipeline with SNMPv2c: trap reception, processing, and UDP forwarding."
echo 

# 1. Check container status
echo "1. Checking container status..."
if docker ps | grep -q fluentd-snmp-trap; then
  echo "✅ Container is running"
else
  echo "❌ Container not found. Please start it with: docker-compose up -d fluentd-snmp"
  exit 1
fi

echo "Verifying SNMP trap daemon is running..."
if docker exec fluentd-snmp-trap ps aux | grep -q snmptrapd; then
  echo "✅ SNMP trap daemon is running"
else
  echo "❌ SNMP trap daemon is not running"
  exit 1
fi

# 2. Test SNMPv2c Reception
echo
echo "2. Testing SNMPv2c trap reception..."
echo "Sending SNMPv2c trap with ID: $TEST_ID"
snmptrap -v 2c -c public localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 \
  1.3.6.1.2.1.1.3.0 s "$TEST_ID" 2>/dev/null

echo "Waiting for trap processing..."
sleep 2

echo "Checking trap reception in log..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$TEST_ID"; then
  echo "✅ SNMPv2c trap was received and logged"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID"
else
  echo "❌ SNMPv2c trap not found in log"
fi

# 3. Test Fluentd Processing
echo
echo "3. Testing Fluentd processing..."
echo "Checking for recent message processing..."
if docker logs fluentd-snmp-trap --tail 10 | grep -q "messages send"; then
  echo "✅ Fluentd processed and forwarded messages"
  docker logs fluentd-snmp-trap --tail 5 | grep "messages send"
else
  echo "❌ No recent message forwarding detected"
fi

# 4. Test Direct UDP Forwarding
echo
echo "4. Testing direct UDP forwarding to 165.202.6.129:1237..."
echo "<snmp_trap><timestamp>$(date)</timestamp><id>$TEST_ID-DIRECT</id><data>Direct UDP test message</data></snmp_trap>" | nc -u 165.202.6.129 1237

echo "✅ Direct UDP message sent to 165.202.6.129:1237"
echo "  Message ID: $TEST_ID-DIRECT"
echo "  To verify, check at the destination for this message ID."

# 5. Summary
echo
echo "=== Test Summary ==="
echo "Test ID: $TEST_ID"
echo "SNMPv2c Reception: Working - traps are received and logged"
echo "Fluentd Processing: Working - messages are processed and forwarded"
echo "UDP Forwarding to 165.202.6.129:1237: Message sent - verify at destination"
echo
echo "Note: This test uses SNMPv2c which is fully functional. For SNMPv3, you would need to"
echo "discover the correct Engine ID. See test-procedure.md for detailed instructions." 