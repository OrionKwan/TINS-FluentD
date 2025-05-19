#!/bin/bash
# Script to verify SNMPv3 configuration and test trap reception inside the container

echo "========================================================================"
echo "🔍 Testing SNMPv3 Configuration"
echo "========================================================================"

# Display the current SNMPv3 configuration
echo -e "\n📋 Current snmptrapd.conf:"
cat /etc/snmp/snmptrapd.conf

# Check if snmptrapd process is running
echo -e "\n🔄 Checking if snmptrapd is running:"
ps aux | grep snmptrapd | grep -v grep

# Check listening ports
echo -e "\n🔌 Checking network ports:"
netstat -nlu | grep 1162

# Check logs for errors
echo -e "\n🚨 Checking for errors in logs:"
grep -i error /var/log/snmptrapd.log | tail -5

# Send a test trap to ourselves for verification
echo -e "\n🔔 Sending a test SNMPv3 trap to localhost:"
# Generate a unique ID for this test
TEST_ID="INTERNAL-TEST-$(date +%s)"

# Send SNMPv3 trap with environment-defined credentials
snmptrap -v 3 -a $SNMPV3_AUTH_PROTOCOL -A $SNMPV3_AUTH_PASS -x $SNMPV3_PRIV_PROTOCOL -X $SNMPV3_PRIV_PASS \
  -l authPriv -u $SNMPV3_USER -On "localhost:1162" '' \
  1.3.6.1.6.3.1.1.5.4 \
  1.3.6.1.2.1.2.2.1.1.1 i 1 \
  1.3.6.1.2.1.2.2.1.2.1 s "$TEST_ID" \
  1.3.6.1.2.1.2.2.1.7.1 i 1 \
  1.3.6.1.2.1.2.2.1.8.1 i 1

echo -e "\n⏳ Waiting 3 seconds for trap processing..."
sleep 3

# Check if the test trap was received
echo -e "\n🔍 Checking if trap was received:"
grep "$TEST_ID" /var/log/snmptrapd.log
if [ $? -eq 0 ]; then
    echo -e "\n✅ SUCCESS: SNMPv3 trap was received and processed correctly!"
else
    echo -e "\n❌ ERROR: SNMPv3 trap was not received or processed."
    echo "Check configuration errors above."
fi

echo -e "\n📊 Last 10 lines of snmptrapd.log:"
tail -10 /var/log/snmptrapd.log

echo -e "\n========================================================================"
echo "🔄 Test Complete"
echo "========================================================================" 