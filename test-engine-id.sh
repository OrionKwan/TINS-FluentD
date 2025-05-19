#!/bin/bash
# Test script for SNMPv3 with the correct Engine ID

# Wait for the container to be ready
sleep 10

# Send a test trap
TEST_ID="FIXED-$(date +%s)"
echo "Sending test SNMPv3 trap with Engine ID: 0x80001F88807C0F9A615F4B0768000000"
snmptrap -v 3 -e 0x80001F88807C0F9A615F4B0768000000 -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID"

sleep 3

# Check if the trap was received
echo "Checking if trap was received..."
if grep -q "$TEST_ID" /var/log/snmptrapd.log; then
  echo "✅ SUCCESS: SNMPv3 trap was received!"
  grep "$TEST_ID" /var/log/snmptrapd.log
else
  echo "❌ FAIL: SNMPv3 trap not found in log."
  echo "Last log entries:"
  tail -n 5 /var/log/snmptrapd.log
fi
