#!/bin/bash
# Test script using numeric OIDs only to test SNMPv3 trap reception

TRAP_ID="NUMERIC-OID-TEST-$(date +%s)"
echo "Sending SNMPv3 trap using numeric OIDs only"
echo "Trap ID: $TRAP_ID"

# Send the trap using numeric OIDs
snmptrap -v 3 -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv -u NCEadmin -e 0x80001F88807C0F9A615F4B0768000000 \
  "192.168.8.100:1162" "" \
  1.3.6.1.6.3.1.1.5.4 \
  1.3.6.1.2.1.1.1.0 s "$TRAP_ID" 

echo "Trap sent, waiting for processing..."
sleep 5

# Check logs
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -10

echo "Checking specifically for this trap ID:"
docker exec fluentd-snmp-trap grep "$TRAP_ID" /var/log/snmptrapd.log || echo "Trap ID not found in logs"

echo "Done" 