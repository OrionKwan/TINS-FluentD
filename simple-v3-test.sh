#!/bin/bash
# Simple SNMPv3 test - let the sender generate its own EngineID

# Create a unique ID for this test
UNIQUE_ID="SIMPLE-V3-$(date +%s)"

echo "Sending SNMPv3 trap with automatic Engine ID..."
echo "User: NCEadmin, Target: localhost:1162"

# Send SNMPv3 trap without specifying Engine ID
snmptrap -v 3 -u NCEadmin -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$UNIQUE_ID" 2>/dev/null

echo "SNMPv3 trap sent"
sleep 2

# Check if it was logged
echo "Checking log for ID: $UNIQUE_ID"
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$UNIQUE_ID" || echo "Trap not found in log" 