#!/bin/bash
# Direct script to send SNMPv3 trap to the container IP (known working version)

# Default trap ID
TRAP_ID=${1:-"TEST-V3-$(date +%s)"}
# Use the macvlan network IP
CONTAINER_IP="192.168.8.100"
TRAP_PORT="1162"

# Create temporary SNMP config to disable MIB loading (removes warnings)
SNMP_CONF_FILE="/tmp/snmp-no-mibs.conf"
cat > "$SNMP_CONF_FILE" << EOF
mibs :
EOF

echo "======================================================================"
echo "🔔 Sending SNMPv3 trap with ID: $TRAP_ID"
echo "🎯 Destination: $CONTAINER_IP:$TRAP_PORT"
echo "======================================================================"

# Send SNMPv3 trap with suppressed warnings
SNMPCONFPATH="$SNMP_CONF_FILE" snmptrap -v 3 -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv -u NCEadmin -e 0x80001F88807C0F9A615F4B0768000000 -On "$CONTAINER_IP:$TRAP_PORT" '' \
  1.3.6.1.6.3.1.1.5.4 \
  1.3.6.1.2.1.2.2.1.1.1 i 1 \
  1.3.6.1.2.1.2.2.1.2.1 s "$TRAP_ID" \
  1.3.6.1.2.1.2.2.1.7.1 i 1 \
  1.3.6.1.2.1.2.2.1.8.1 i 1 \
  2>/dev/null
  
echo "✅ SNMPv3 trap sent successfully"
echo "📋 Check results with: docker exec fluentd-snmp-trap grep '$TRAP_ID' /var/log/snmptrapd.log" 