#!/bin/bash
# Test script to directly inject SNMP trap log entries and monitor processing

# Generate unique test ID
TEST_ID="DIRECT-TEST-$(date +%s)"

echo "=== Direct SNMP Trap Injection Test ==="
echo "Test ID: $TEST_ID"
echo

# Directly inject a trap log entry
echo "1. Injecting trap entry directly into snmptrapd.log..."
TRAP_DATA="SNMPTRAP: $(date +"%Y-%m-%d %H:%M:%S") sysUpTimeInstance \"$TEST_ID\""
FORMAT_DATA="FORMATTED: <trap><timestamp>$(date +"%Y-%m-%d %H:%M:%S")</timestamp><data>sysUpTimeInstance \"$TEST_ID\"</data></trap>"

docker exec fluentd-snmp-trap sh -c "echo '$TRAP_DATA' >> /var/log/snmptrapd.log"
docker exec fluentd-snmp-trap sh -c "echo '$FORMAT_DATA' >> /var/log/snmptrapd.log"

echo "Trap injected at $(date)"
echo

# Wait for processing
echo "2. Waiting for processing..."
sleep 5

# Check logs to see if processed
echo "3. Checking Fluentd logs for processing..."
docker logs --since 30s fluentd-snmp-trap | grep -i "$TEST_ID" | head -n 10
echo

# Check Kafka
echo "4. Checking Kafka for the message..."
docker exec kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic snmp_traps --from-beginning --max-messages 30 2>/dev/null | grep -i "$TEST_ID"
echo

echo "Test completed." 