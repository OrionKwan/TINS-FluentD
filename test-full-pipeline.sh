#!/bin/bash
# Comprehensive test script for the entire SNMP trap pipeline
# Tests: SNMP trap reception → snmptrapd → Fluentd → Kafka & UDP outputs

set -e  # Exit on error

echo "=== SNMP Pipeline Full Test ==="
echo "This test will verify the entire pipeline from SNMP trap reception to delivery."

# Define constants
ENGINE_ID="0x80001F88807C0F9A615F4B0768000000"
TEST_ID="PIPELINE-TEST-$(date +%s)"
KAFKA_TOPIC="${KAFKA_TOPIC:-snmp_traps}"
UDP_HOST="${UDP_FORWARD_HOST:-165.202.6.129}"
UDP_PORT="${UDP_FORWARD_PORT:-1237}"

# Create a temporary directory for test artifacts
echo "Setting up test environment..."
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Function to check if a container is running
check_container() {
  if ! docker ps | grep -q "$1"; then
    echo "❌ ERROR: Container $1 is not running"
    exit 1
  fi
}

# Check if required containers are running
echo "1. Verifying required containers are running..."
check_container "fluentd-snmp-trap"
check_container "kafka"
echo "✅ Required containers are running"

# Setup UDP listener to verify UDP output
echo "2. Setting up UDP listener for testing..."
echo "Starting netcat listener on port 7777 to simulate UDP endpoint..."
nc -u -l 7777 > "$TEMP_DIR/udp_output.txt" &
NC_PID=$!
trap "kill $NC_PID 2>/dev/null || true; rm -rf $TEMP_DIR" EXIT

# Update UDP endpoint to point to our test listener
echo "3. Temporarily redirecting UDP output to test listener..."
docker exec fluentd-snmp-trap sh -c "sed -i 's/host \".*\"/host \"172.17.0.1\"/g' /fluentd/etc/fluent.conf"
docker exec fluentd-snmp-trap sh -c "sed -i 's/port \".*\"/port \"7777\"/g' /fluentd/etc/fluent.conf"

# Setup Kafka consumer to verify Kafka output
echo "4. Setting up Kafka consumer..."
docker exec -d kafka sh -c "kafka-console-consumer --bootstrap-server localhost:9092 --topic $KAFKA_TOPIC --from-beginning > /tmp/kafka_output.txt &"
KAFKA_CONSUMER_PID=$!

# Restart Fluentd to apply config changes
echo "5. Restarting Fluentd to apply UDP configuration change..."
docker exec fluentd-snmp-trap sh -c "pkill -f fluentd || true; sleep 2; fluentd -c /fluentd/etc/fluent.conf -p /fluentd/plugins &"
sleep 5

# Send test SNMP trap
echo "6. Sending test SNMP trap with ID: $TEST_ID"
docker exec fluentd-snmp-trap snmptrap -v 3 \
  -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID"

# Wait for processing
echo "7. Waiting for pipeline processing (15s)..."
sleep 15

# Check snmptrapd log
echo "8. Checking SNMP trap reception..."
if docker exec fluentd-snmp-trap grep -q "$TEST_ID" /var/log/snmptrapd.log; then
  echo "✅ STAGE 1 SUCCESS: SNMP trap was received by snmptrapd"
  TRAP_LOG=$(docker exec fluentd-snmp-trap grep "$TEST_ID" /var/log/snmptrapd.log)
  echo "Log: $TRAP_LOG"
else
  echo "❌ STAGE 1 FAIL: SNMP trap was not received by snmptrapd"
  echo "Last 5 log entries:"
  docker exec fluentd-snmp-trap tail -n 5 /var/log/snmptrapd.log
  exit 1
fi

# Check Fluentd logs
echo "9. Checking Fluentd processing..."
if docker logs fluentd-snmp-trap | grep -q "snmp.trap"; then
  echo "✅ STAGE 2 SUCCESS: Fluentd processed the trap event"
else
  echo "❌ STAGE 2 FAIL: Fluentd did not process the trap event"
  echo "Last 10 log entries:"
  docker logs fluentd-snmp-trap | tail -n 10
  exit 1
fi

# Check buffer files
echo "10. Checking buffer status..."
echo "Buffer files:"
docker exec fluentd-snmp-trap ls -la /fluentd/buffer/kafka /fluentd/buffer/error 2>/dev/null || echo "No buffer files found (might be normal if flushed)"

# Check UDP output
echo "11. Checking UDP output..."
sleep 2  # Give time for UDP packet to arrive
kill $NC_PID 2>/dev/null || true

if grep -q "$TEST_ID" "$TEMP_DIR/udp_output.txt"; then
  echo "✅ STAGE 3 SUCCESS: Trap data was received by UDP endpoint"
  echo "UDP Output:"
  cat "$TEMP_DIR/udp_output.txt"
else
  echo "❌ STAGE 3 FAIL: Trap data was not received by UDP endpoint"
  echo "UDP Output (if any):"
  cat "$TEMP_DIR/udp_output.txt"
fi

# Check Kafka output
echo "12. Checking Kafka output..."
docker exec kafka sh -c "cat /tmp/kafka_output.txt" > "$TEMP_DIR/kafka_data.txt"
if grep -q "$TEST_ID" "$TEMP_DIR/kafka_data.txt"; then
  echo "✅ STAGE 4 SUCCESS: Trap data was sent to Kafka"
  echo "Kafka Output:"
  grep "$TEST_ID" "$TEMP_DIR/kafka_data.txt"
else
  echo "❌ STAGE 4 FAIL: Trap data was not sent to Kafka or not found"
  echo "Kafka Consumer Output (if any):"
  cat "$TEMP_DIR/kafka_data.txt"
fi

# Clean up Kafka consumer
docker exec kafka sh -c "pkill -f kafka-console-consumer || true"

# Restore original UDP configuration
echo "13. Restoring original UDP configuration..."
docker exec fluentd-snmp-trap sh -c "sed -i 's/host \"172.17.0.1\"/host \"${UDP_HOST}\"/g' /fluentd/etc/fluent.conf"
docker exec fluentd-snmp-trap sh -c "sed -i 's/port \"7777\"/port \"${UDP_PORT}\"/g' /fluentd/etc/fluent.conf"

# Restart Fluentd to apply original config
docker exec fluentd-snmp-trap sh -c "pkill -f fluentd || true; sleep 2; fluentd -c /fluentd/etc/fluent.conf -p /fluentd/plugins &"
sleep 3

# Check for any errors
echo "14. Checking for errors..."
if docker exec fluentd-snmp-trap ls -la /fluentd/log 2>/dev/null | grep -q "error_"; then
  echo "⚠️ WARNING: Error logs found"
  docker exec fluentd-snmp-trap ls -la /fluentd/log | grep "error_"
  docker exec fluentd-snmp-trap cat /fluentd/log/error_*.log | tail -n 10
else
  echo "✅ No error logs found"
fi

# Summary
echo 
echo "=== Pipeline Test Summary ==="
echo "✅ STAGE 1: SNMP Trap Reception - $(docker exec fluentd-snmp-trap grep -q "$TEST_ID" /var/log/snmptrapd.log && echo SUCCESS || echo FAIL)"
echo "✅ STAGE 2: Fluentd Processing - $(docker logs fluentd-snmp-trap | grep -q "snmp.trap" && echo SUCCESS || echo FAIL)"
echo "$(grep -q "$TEST_ID" "$TEMP_DIR/udp_output.txt" && echo "✅" || echo "❌") STAGE 3: UDP Output Delivery"
echo "$(grep -q "$TEST_ID" "$TEMP_DIR/kafka_data.txt" && echo "✅" || echo "❌") STAGE 4: Kafka Output Delivery"
echo
echo "Test trap ID: $TEST_ID"
echo
echo "=== Test Completed ==="

# Remove temporary files
rm -rf "$TEMP_DIR" 