#!/bin/bash
# Test script with the correct Engine ID: 0x80001F88807C0F9A615F4B0768000000

# Get container IP address
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fluentd-snmp-trap)

# SNMPv3 Credentials
SNMPV3_USER="NCEadmin"
AUTH_PROTOCOL="MD5"
AUTH_PASS="P@ssw0rdauth"
PRIV_PROTOCOL="AES"
PRIV_PASS="P@ssw0rddata"
ENGINE_ID="0x80001F88807C0F9A615F4B0768000000"

# Generate unique test ID
TEST_ID="CORRECT-ENGINE-$(date +%s)"

echo "=== Testing SNMPv3 with Correct Engine ID ==="
echo "Target: $CONTAINER_IP:1162"
echo "Username: $SNMPV3_USER"
echo "Auth Protocol: $AUTH_PROTOCOL"
echo "Privacy Protocol: $PRIV_PROTOCOL"
echo "Engine ID: $ENGINE_ID"
echo "Test ID: $TEST_ID"
echo

echo "Sending SNMPv3 trap with correct Engine ID..."
# Use container's IP address
snmptrap -v 3 -e $ENGINE_ID -u $SNMPV3_USER \
  -a $AUTH_PROTOCOL -A $AUTH_PASS \
  -x $PRIV_PROTOCOL -X $PRIV_PASS \
  -l authPriv $CONTAINER_IP:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID" 2>&1

echo "Trap sent. Waiting for processing..."
sleep 3

echo "Checking if trap was received by local trap daemon..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap with correct Engine ID was received!"
  echo "Log entry:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID"
else
  echo "❌ FAIL: SNMPv3 trap was not received by the local trap daemon."
  echo "Last 5 log entries:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5
fi

# Check if trap was forwarded to Kafka
echo
echo "Checking if trap was forwarded to Kafka..."
sleep 2
if docker exec kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic snmp_traps --from-beginning --max-messages 10 2>/dev/null | grep -q "$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap was forwarded to Kafka!"
else
  echo "❌ FAIL: SNMPv3 trap was not forwarded to Kafka or could not be found."
  echo "Last 3 Kafka messages in topic 'snmp_traps':"
  docker exec kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic snmp_traps --from-beginning --max-messages 3 2>/dev/null
fi

# Check Fluentd logs for UDP forwarding
echo
echo "Checking Fluentd logs for UDP forwarding..."
if docker logs fluentd-snmp-trap | grep -q "UDP_FORWARD_HOST.*$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap appears to have been forwarded to UDP destination!"
  docker logs fluentd-snmp-trap | grep -A 2 -B 2 "$TEST_ID" | grep "UDP"
else
  echo "⚠️ WARNING: Could not confirm UDP forwarding in logs. This doesn't necessarily mean it failed."
  echo "Fluentd logs from around the time of trap processing:"
  docker logs fluentd-snmp-trap | tail -n 10
fi

# Testing direct UDP forwarding
echo
echo "Testing direct UDP forwarding to 165.202.6.129:1237..."
echo "<snmp_trap><timestamp>$(date)</timestamp><version>SNMPv3</version><user>$SNMPV3_USER</user><engineID>$ENGINE_ID</engineID><id>$TEST_ID-DIRECT</id></snmp_trap>" | nc -u 165.202.6.129 1237
echo "✅ Direct UDP message sent to 165.202.6.129:1237"

echo
echo "Test complete. Check the destination systems to confirm reception at 165.202.6.129:1237."
