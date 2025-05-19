#!/bin/bash
#
# Enhanced test script to send SNMPv3 traps to the fluentd-snmp plugin
#

# Default configuration - can be overridden by environment variables
TRAP_DESTINATION=${TRAP_DESTINATION:-"localhost"}
TRAP_PORT=${TRAP_PORT:-1162}
SNMPV3_USER=${SNMPV3_USER:-"NCEadmin"}
SNMPV3_AUTH_PROTOCOL=${SNMPV3_AUTH_PROTOCOL:-"SHA"}
SNMPV3_AUTH_PASS=${SNMPV3_AUTH_PASS:-"P@ssw0rdauth"}
SNMPV3_PRIV_PROTOCOL=${SNMPV3_PRIV_PROTOCOL:-"AES"}
SNMPV3_PRIV_PASS=${SNMPV3_PRIV_PASS:-"P@ssw0rddata"}

# Skip MIB loading to avoid errors
export MIBS=""

echo "Sending SNMPv3 trap to ${TRAP_DESTINATION}:${TRAP_PORT}"
echo "Using auth: ${SNMPV3_AUTH_PROTOCOL}, priv: ${SNMPV3_PRIV_PROTOCOL}"

# Send a generic trap with numeric OIDs (no MIB dependencies)
snmptrap -v 3 -a SHA -A ${SNMPV3_AUTH_PASS} -x AES -X ${SNMPV3_PRIV_PASS} \
  -l authPriv -u ${SNMPV3_USER} -e 0x0102030405 \
  ${TRAP_DESTINATION}:${TRAP_PORT} '' \
  1.3.6.1.6.3.1.1.5.3 \
  1.3.6.1.2.1.2.2.1.1.1 i 1 \
  1.3.6.1.2.1.2.2.1.2.1 s "GigabitEthernet1/0/1" \
  1.3.6.1.2.1.2.2.1.7.1 i 1 \
  1.3.6.1.2.1.2.2.1.8.1 i 2

sleep 1

# Send a custom alarm trap
echo "Sending custom alarm trap..."
snmptrap -v 3 -a SHA -A ${SNMPV3_AUTH_PASS} -x AES -X ${SNMPV3_PRIV_PASS} \
  -l authPriv -u ${SNMPV3_USER} -e 0x0102030405 \
  ${TRAP_DESTINATION}:${TRAP_PORT} '' \
  1.3.6.1.4.1.9.9.385.1.2.1.0 \
  1.3.6.1.4.1.9.9.385.1.2.1.0 i 3 \
  1.3.6.1.4.1.9.9.385.1.2.2.0 i 1 \
  1.3.6.1.4.1.9.9.385.1.2.3.0 s "Network connection issue detected"

echo "Traps sent successfully"
