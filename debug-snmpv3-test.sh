#!/bin/bash
# Debug test script for SNMPv3

# SNMPv3 Credentials
SNMPV3_USER="NCEadmin"
AUTH_PROTOCOL="MD5"
AUTH_PASS="P@ssw0rdauth"
PRIV_PROTOCOL="AES"
PRIV_PASS="P@ssw0rddata"

# Generate unique test ID
TEST_ID="DEBUG-SNMPV3-$(date +%s)"

echo "=== DEBUG Testing SNMPv3 ==="
echo "Username: $SNMPV3_USER"
echo "Auth Protocol: $AUTH_PROTOCOL"
echo "Privacy Protocol: $PRIV_PROTOCOL"
echo "Test ID: $TEST_ID"
echo

echo "Starting snmptrapd in debug mode in container..."
docker exec -d fluentd-snmp-trap sh -c "pkill -f snmptrapd && snmptrapd -Lo -Dusm,trap,auth,tdomain,snmp -f -c /etc/snmp/snmptrapd.conf 0.0.0.0:1162 > /var/log/snmptrapd-debug-output.log 2>&1"
sleep 3
echo "Debug snmptrapd started."

echo "Sending SNMPv3 trap with verbose debugging..."
snmptrap -v 3 -u $SNMPV3_USER \
  -a $AUTH_PROTOCOL -A $AUTH_PASS \
  -x $PRIV_PROTOCOL -X $PRIV_PASS \
  -l authPriv \
  -d localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID" 2>&1 | tee snmp-sender-debug.log

echo "Trap sent. Waiting for processing..."
sleep 3

echo "Checking debug logs..."
echo "-------- SENDER DEBUG OUTPUT --------"
tail -n 20 snmp-sender-debug.log || echo "No sender debug log available"

echo
echo "-------- RECEIVER DEBUG OUTPUT --------"
docker exec fluentd-snmp-trap cat /var/log/snmptrapd-debug-output.log | tail -n 30 || echo "No receiver debug log available"

echo
echo "Checking if trap was received..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap was received!"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID"
else
  echo "❌ FAIL: SNMPv3 trap was not received in normal log."
fi

# Restart the normal snmptrapd
echo
echo "Restarting normal snmptrapd..."
docker exec -d fluentd-snmp-trap sh -c "pkill -f snmptrapd && snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf 0.0.0.0:1162"
sleep 1
echo "Normal operation restored." 