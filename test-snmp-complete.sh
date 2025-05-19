#!/bin/bash
# Comprehensive SNMP test script

# Get the IP of the fluentd-snmp container
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fluentd-snmp-trap)
echo "Fluentd SNMP trap container IP: $CONTAINER_IP"

# SNMPv3 trap parameters
SNMPV3_USER="NCEadmin"
SNMPV3_AUTH_PASS="P@ssw0rdauth"
SNMPV3_PRIV_PASS="P@ssw0rddata"
SNMPV3_AUTH_PROTOCOL="SHA"
SNMPV3_PRIV_PROTOCOL="AES"
TRAP_PORT=1162

# Create a timestamp for this test
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
TEST_ID=$(date +"%s")

# Display test info
echo "============================================="
echo "SNMPv3 Trap Pipeline Test ($TIMESTAMP)"
echo "============================================="
echo "Step 1: Sending SNMPv3 trap to $CONTAINER_IP:$TRAP_PORT"
echo "Test ID: $TEST_ID"

# Send the SNMPv3 trap
snmptrap -v 3 -a SHA -A $SNMPV3_AUTH_PASS -x AES -X $SNMPV3_PRIV_PASS \
  -l authPriv -u $SNMPV3_USER -e 0x0102030405 \
  $CONTAINER_IP:$TRAP_PORT '' \
  1.3.6.1.4.1.9.9.385.1.2.1.0 \
  1.3.6.1.4.1.9.9.385.1.2.1.0 i 3 \
  1.3.6.1.4.1.9.9.385.1.2.3.0 s "Complete pipeline test trap ($TEST_ID)"

echo "Trap sent. Waiting for processing..."
sleep 3

echo "============================================="
echo "Step 2: Checking snmptrapd.log in container"
echo "============================================="
docker exec -it fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID" | tail -5

echo "============================================="
echo "Step 3: Checking Fluentd processing"
echo "============================================="
docker logs fluentd-snmp-trap | grep "$TEST_ID" | tail -5

echo "============================================="
echo "Step 4: Checking Kafka output"
echo "============================================="
echo "Running Kafka consumer (press Ctrl+C after a few messages)..."
echo "docker exec -it kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic snmp_traps --from-beginning | grep '$TEST_ID'"

echo "============================================="
echo "Step 5: To check UDP output"
echo "============================================="
echo "Run in a separate terminal: ./capture-udp.sh"
echo "This will capture UDP messages on port 1237"

echo "Test complete!"
