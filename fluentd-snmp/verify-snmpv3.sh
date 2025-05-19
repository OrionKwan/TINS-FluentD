#!/bin/bash
# Script to verify SNMPv3 trap reception

# Generate a unique trap ID
TRAP_ID="VERIFY-SNMPv3-$(date +%s)"
TARGET_IP="192.168.8.100"
TARGET_PORT="1162"

echo "========================================================================"
echo "🔍 Verifying SNMPv3 Trap Reception"
echo "========================================================================"

# Check current configuration in the container
echo -e "\n📋 Current SNMPv3 configuration in container:"
docker exec fluentd-snmp-trap grep -A 5 createUser /etc/snmp/snmptrapd.conf

# Check if snmptrapd is running in the container
echo -e "\n🔄 Checking if snmptrapd is running:"
docker exec fluentd-snmp-trap ps aux | grep snmptrapd | grep -v grep

# Check network ports
echo -e "\n🔌 Checking network ports:"
docker exec fluentd-snmp-trap netstat -nlu | grep 1162

# Send a test trap
echo -e "\n🔔 Sending test SNMPv3 trap with ID: $TRAP_ID"
echo "🎯 Destination: $TARGET_IP:$TARGET_PORT"

# Create temporary SNMP config to disable MIB loading (removes warnings)
SNMP_CONF_FILE="/tmp/snmp-no-mibs.conf"
cat > "$SNMP_CONF_FILE" << EOF
mibs :
EOF

# Send SNMPv3 trap with same credentials as configured in the container
SNMPCONFPATH="$SNMP_CONF_FILE" snmptrap -v 3 -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv -u NCEadmin -e 0x80001F88807C0F9A615F4B0768000000 -On "$TARGET_IP:$TARGET_PORT" '' \
  1.3.6.1.6.3.1.1.5.4 \
  1.3.6.1.2.1.2.2.1.1.1 i 1 \
  1.3.6.1.2.1.2.2.1.2.1 s "$TRAP_ID" \
  1.3.6.1.2.1.2.2.1.7.1 i 1 \
  1.3.6.1.2.1.2.2.1.8.1 i 1 \
  2>/dev/null

echo -e "\n⏳ Waiting 5 seconds for trap processing..."
sleep 5

# Check if the trap was received in snmptrapd.log
echo -e "\n🔍 Checking if trap was received:"
docker exec fluentd-snmp-trap grep "$TRAP_ID" /var/log/snmptrapd.log

if [ $? -eq 0 ]; then
    echo -e "\n✅ SUCCESS: SNMPv3 trap was received and processed correctly!"
else
    echo -e "\n❌ ERROR: SNMPv3 trap was not received or processed."
    
    # Show current logs for debugging
    echo -e "\n📊 Last 10 lines of snmptrapd.log:"
    docker exec fluentd-snmp-trap tail -10 /var/log/snmptrapd.log
    
    echo -e "\n🔍 Checking for errors in logs:"
    docker exec fluentd-snmp-trap grep -i error /var/log/snmptrapd.log | tail -5
fi

echo -e "\n========================================================================"
echo "🔄 Verification Complete"
echo "========================================================================" 