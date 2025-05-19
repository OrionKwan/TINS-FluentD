#!/bin/bash
#
# Simplified SNMPv3 trap test script with matching parameters
#

# Set target and ID
TRAP_DESTINATION="localhost"
TRAP_PORT="1162"
UNIQUE_ID="FIXED-SNMPv3-$(date +%s)"

# SNMPv3 parameters - MUST match snmptrapd.conf exactly
SNMPV3_USER="NCEadmin"
SNMPV3_AUTH_PASS="P@ssw0rdauth"
SNMPV3_PRIV_PASS="P@ssw0rddata"
SNMPV3_ENGINE_ID="0102030405"  # Must match the one in snmptrapd.conf

echo "========================================================================"
echo "🔔 Sending SNMPv3 trap with engineID 0x$SNMPV3_ENGINE_ID"
echo "🎯 Destination: $TRAP_DESTINATION:$TRAP_PORT"
echo "👤 User: $SNMPV3_USER with ID: $UNIQUE_ID"
echo "========================================================================"

# Send trap with minimal parameters, matching exactly what's in snmptrapd.conf
snmptrap -v 3 -e 0x$SNMPV3_ENGINE_ID -u $SNMPV3_USER \
  -a SHA -A $SNMPV3_AUTH_PASS \
  -x AES -X $SNMPV3_PRIV_PASS \
  -l authPriv \
  $TRAP_DESTINATION:$TRAP_PORT '' \
  1.3.6.1.6.3.1.1.5.1 \
  1.3.6.1.2.1.1.3.0 s "$UNIQUE_ID" 2>/dev/null

echo "✅ SNMPv3 trap sent"
echo "⏳ Waiting for trap processing..."
sleep 2

# Check if the trap was logged
echo "📋 Checking trap log for our ID '$UNIQUE_ID'..."
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$UNIQUE_ID" || echo "❌ Trap not found in log!"

# Try a simple v2c trap as a control
echo
echo "🔄 Sending an SNMPv2c trap as a control test..."
snmptrap -v 2c -c public $TRAP_DESTINATION:$TRAP_PORT '' 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "CONTROL-V2-$UNIQUE_ID" 2>/dev/null
sleep 1
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "CONTROL-V2-$UNIQUE_ID" && echo "✅ SNMPv2c trap was received"

# Test direct UDP forwarding
echo 
echo "🧪 Testing direct UDP forwarding..."
echo "<snmp_trap><timestamp>$(date)</timestamp><test>engineID-matching</test><uniqueId>$UNIQUE_ID</uniqueId></snmp_trap>" | nc -u 165.202.6.129 1237
echo "✅ Direct UDP message sent to 165.202.6.129:1237" 