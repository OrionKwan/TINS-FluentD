#!/bin/bash
# Simple script to test SNMPv3 trap reception with numeric OIDs

TRAP_ID="SIMPLE-TEST-$(date +%s)"
echo "Sending simple test trap with ID: $TRAP_ID"

# Send trap with numeric OIDs
snmptrap -v 3 -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv -u NCEadmin -e 0x80001F88807C0F9A615F4B0768000000 \
  "192.168.8.100:1162" "" \
  1.3.6.1.6.3.1.1.5.4 \
  1.3.6.1.2.1.1.5.0 s "$TRAP_ID" 2>/dev/null

echo "Trap sent, checking logs after 5 seconds..."
sleep 5

# Check logs
docker exec fluentd-snmp-trap grep "$TRAP_ID" /var/log/snmptrapd.log || echo "Trap not found in logs"
echo "Done" 