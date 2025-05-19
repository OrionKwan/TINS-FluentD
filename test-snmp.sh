#!/bin/bash
# Simple test script for SNMPv3 trap reception

# Generate unique trap ID
TRAP_ID="TEST-$(date +%s)"

echo "Sending SNMPv3 trap to 192.168.8.100:1162 with ID: $TRAP_ID"

# Send SNMPv3 trap 
snmptrap -v 3 -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv -u NCEadmin -e 0x80001F88807C0F9A615F4B0768000000 \
  "192.168.8.100:1162" "" \
  1.3.6.1.6.3.1.1.5.4 \
  1.3.6.1.2.1.2.2.1.2.1 s "$TRAP_ID" 2>/dev/null

echo "Waiting 5 seconds for processing..."
sleep 5

echo "Checking for trap in logs:"
docker exec fluentd-snmp-trap grep "$TRAP_ID" /var/log/snmptrapd.log 