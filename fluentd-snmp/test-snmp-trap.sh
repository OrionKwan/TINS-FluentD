#!/bin/bash
# Script to send a test SNMPv3 trap to the fluentd-snmp container

# Generate a unique trap ID
TRAP_ID="TEST-$(date +%s)"

echo "====================================================================="
echo "🔔 Sending SNMPv3 trap with ID: $TRAP_ID"
echo "🎯 Destination: 192.168.8.100:1162"
echo "====================================================================="

# Send the SNMPv3 trap
snmptrap -v 3 -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv -u NCEadmin -e 0x80001F88807C0F9A615F4B0768000000 \
  "192.168.8.100:1162" "" \
  1.3.6.1.6.3.1.1.5.4 \
  1.3.6.1.2.1.2.2.1.1.1 i 1 \
  1.3.6.1.2.1.2.2.1.2.1 s "$TRAP_ID" \
  1.3.6.1.2.1.2.2.1.7.1 i 1 \
  1.3.6.1.2.1.2.2.1.8.1 i 1 2>/dev/null

echo "✅ SNMPv3 trap sent successfully"
echo "⏳ Waiting 5 seconds for processing..."
sleep 5

# Check if the trap was received
echo "🔍 Checking if trap was received:"
docker exec fluentd-snmp-trap grep "$TRAP_ID" /var/log/snmptrapd.log

if [ $? -eq 0 ]; then
    echo "✅ SUCCESS: SNMPv3 trap was received and processed correctly!"
else
    echo "❌ ERROR: SNMPv3 trap was not received or processed."
    
    # Show current logs for debugging
    echo "📊 Last 10 lines of snmptrapd.log:"
    docker exec fluentd-snmp-trap tail -10 /var/log/snmptrapd.log
fi

echo "====================================================================="
echo "🔄 Test Complete"
echo "=====================================================================" 