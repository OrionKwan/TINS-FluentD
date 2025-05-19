#!/bin/bash
# Script to trace SNMP trap processing through the system

# Generate unique test ID
TEST_ID="TRACE-ID-$(date +%s)"

echo "=== SNMP Trap Processing Trace ==="
echo "Test ID: $TEST_ID"
echo

# 1. Check current Fluentd logs before sending trap
echo "1. Current Fluentd logs before trap (last 5 lines):"
docker logs fluentd-snmp-trap | tail -n 5
echo

# 2. Send test trap with unique ID
echo "2. Sending formatted trap with ID $TEST_ID..."
FORMATTED_DATA="<trap><timestamp>$(date +"%Y-%m-%d %H:%M:%S")</timestamp><data>Trace test with ID $TEST_ID</data></trap>"
docker exec fluentd-snmp-trap sh -c "echo 'FORMATTED: $FORMATTED_DATA' >> /var/log/snmptrapd.log"
echo "Trap sent at $(date)"
echo

# 3. Verify it's in the log file 
echo "3. Verifying trap in snmptrapd.log:"
sleep 1
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -A 1 -B 1 "$TEST_ID"
echo

# 4. Watch for file tail events from Fluentd
echo "4. Watching Fluentd logs for file tail events (10 sec)..."
docker logs --since 1m fluentd-snmp-trap | grep -i "tail" | tail -n 5
echo

# 5. Check for parser events
echo "5. Checking for parser events..."
sleep 2
docker logs --since 1m fluentd-snmp-trap | grep -i "parser\|error" | grep -v "debug" | tail -n 10
echo

# 6. Check for Kafka output
echo "6. Checking for Kafka output events..."
docker logs --since 1m fluentd-snmp-trap | grep -i "kafka" | grep -v "debug" | tail -n 10
echo

# 7. Check for UDP output
echo "7. Checking for UDP remote_syslog events..."
docker logs --since 1m fluentd-snmp-trap | grep -i "remote_syslog\|udp" | grep -v "debug" | tail -n 15
echo

# 8. Check Kafka topic directly
echo "8. Checking Kafka topic for messages with test ID..."
docker exec kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic snmp_traps --from-beginning --max-messages 10 2>/dev/null | grep "$TEST_ID"
echo

echo "=== Trace complete ===" 