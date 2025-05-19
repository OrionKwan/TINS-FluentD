#!/bin/bash
# Test script sending properly formatted SNMP trap

# Generate unique test ID
TEST_ID="FORMAT-TEST-$(date +%s)"

echo "=== Testing with correctly formatted trap data ==="
echo "Test ID: $TEST_ID"
echo

# Format that matches the regex: /<trap><timestamp>(?<xml_timestamp>.*)<\/timestamp><data>(?<xml_data>.*)<\/data><\/trap>/
FORMATTED_DATA="<trap><timestamp>$(date +"%Y-%m-%d %H:%M:%S")</timestamp><data>This is a test trap with ID $TEST_ID</data></trap>"

echo "Sending direct formatted data to snmptrapd.log..."
docker exec fluentd-snmp-trap sh -c "echo 'FORMATTED: $FORMATTED_DATA' >> /var/log/snmptrapd.log"

echo "Data sent. Waiting for processing..."
sleep 3

# Check if processed in logs
echo "Checking if data was processed by Fluentd..."
if docker logs fluentd-snmp-trap | grep -q "$TEST_ID"; then
  echo "✅ SUCCESS: Formatted data was processed by Fluentd!"
  echo "Log entries containing the test ID:"
  docker logs fluentd-snmp-trap | grep "$TEST_ID"
else
  echo "❌ FAIL: Formatted data was not processed or could not be found in logs."
  echo "Recent log entries:"
  docker logs fluentd-snmp-trap | tail -n 10
fi

# Check Kafka 
echo
echo "Checking if data was forwarded to Kafka..."
sleep 2
if docker exec kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic snmp_traps --from-beginning --max-messages 10 2>/dev/null | grep -q "$TEST_ID"; then
  echo "✅ SUCCESS: Data was forwarded to Kafka!"
else
  echo "❌ FAIL: Data was not forwarded to Kafka or could not be found."
  echo "Last 3 Kafka messages in topic 'snmp_traps':"
  docker exec kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic snmp_traps --from-beginning --max-messages 3 2>/dev/null
fi

echo
echo "Test complete." 