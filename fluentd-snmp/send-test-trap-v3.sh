#!/bin/bash
# Script to send a test SNMPv3 trap with MIB OIDs to the fluentd-snmp container

# Generate a unique trap ID
TRAP_ID="MIB-TEST-$(date +%s)"

echo "====================================================================="
echo "🔔 Sending SNMPv3 trap with MIBs and ID: $TRAP_ID"
echo "🎯 Destination: 192.168.8.100:1162"
echo "====================================================================="

# Send the SNMPv3 trap with MIB OIDs
snmptrap -v 3 -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv -u NCEadmin -e 0x80001F88807C0F9A615F4B0768000000 \
  "192.168.8.100:1162" "" \
  IMAP-NORTHBOUND-MIB::imapLinkDown \
  T2000-NETMANAGEMENT-MIB::t2000NetVersion s "$TRAP_ID" \
  2>/dev/null

echo "✅ SNMPv3 trap with MIB OIDs sent"
echo "⏳ Waiting 5 seconds for processing..."
sleep 5

# Check if the trap was received
echo "🔍 Checking if trap was received:"
docker exec fluentd-snmp-trap grep "$TRAP_ID" /var/log/snmptrapd.log

if [ $? -eq 0 ]; then
    echo "✅ SUCCESS: SNMPv3 trap with MIB OIDs was received and processed correctly!"
else
    echo "❌ ERROR: SNMPv3 trap was not received or processed."
    
    # Show current logs for debugging
    echo "📊 Last 10 lines of snmptrapd.log:"
    docker exec fluentd-snmp-trap tail -10 /var/log/snmptrapd.log
    
    # Check if snmptrapd is running
    echo "🔍 Checking if snmptrapd is running:"
    docker exec fluentd-snmp-trap ps aux | grep -v grep | grep snmptrapd
fi

echo "====================================================================="
echo "🔄 Test Complete"
echo "=====================================================================" 