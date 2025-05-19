#!/bin/bash
# Chaos test script for SNMP trap pipeline
# Tests the pipeline's resilience when destinations are unavailable

set -e  # Exit on error

echo "=== SNMP Pipeline Chaos Test ==="
echo "This test will verify the pipeline's resilience when destinations are unavailable."

# Define constants
ENGINE_ID="0x80001F88807C0F9A615F4B0768000000"
TEST_PREFIX="CHAOS-TEST-"
KAFKA_NETWORK="mvp-setup_opensearch-net"

# Create a temporary directory for test artifacts
echo "Setting up test environment..."
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Ensure the container is running
if ! docker ps | grep -q "fluentd-snmp-trap"; then
  echo "❌ ERROR: Container fluentd-snmp-trap is not running"
  exit 1
fi

# Ensure the kafka container is running
if ! docker ps | grep -q "kafka"; then
  echo "❌ ERROR: Container kafka is not running"
  exit 1
fi

# Clean out existing buffer files
echo "Cleaning out existing buffer files..."
docker exec fluentd-snmp-trap sh -c "rm -rf /fluentd/buffer/kafka/* /fluentd/buffer/error/* /fluentd/log/error_*" || true

# Count existing traps to establish baseline
BASELINE_COUNT=$(docker exec fluentd-snmp-trap grep -c "SNMPTRAP:" /var/log/snmptrapd.log || echo 0)
echo "Baseline trap count: $BASELINE_COUNT"

# Test 1: Kafka Outage
echo "=== Test 1: Kafka Outage ==="
echo "1. Disconnecting Kafka from the network..."
docker network disconnect $KAFKA_NETWORK kafka

echo "2. Sending test SNMP trap during Kafka outage..."
TEST_ID_1="${TEST_PREFIX}KAFKA-DOWN-$(date +%s)"
docker exec fluentd-snmp-trap snmptrap -v 3 \
  -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID_1"

echo "3. Waiting for buffer retry attempts (15s)..."
sleep 15

echo "4. Checking buffer files during outage..."
docker exec fluentd-snmp-trap ls -la /fluentd/buffer/kafka 2>/dev/null || echo "No buffer files found"

echo "5. Reconnecting Kafka to the network..."
docker network connect $KAFKA_NETWORK kafka

echo "6. Waiting for buffer flush after Kafka return (30s)..."
sleep 30

# Test 2: UDP Endpoint Unavailable
echo "=== Test 2: UDP Endpoint Unavailable ==="
echo "1. Redirecting UDP traffic to unavailable endpoint..."
ORIG_UDP_HOST=$(docker exec fluentd-snmp-trap grep -o 'host "[^"]*"' /fluentd/etc/fluent.conf | cut -d'"' -f2)
ORIG_UDP_PORT=$(docker exec fluentd-snmp-trap grep -o 'port "[^"]*"' /fluentd/etc/fluent.conf | cut -d'"' -f2)

docker exec fluentd-snmp-trap sh -c "sed -i 's/host \".*\"/host \"1.2.3.4\"/g' /fluentd/etc/fluent.conf"
docker exec fluentd-snmp-trap sh -c "sed -i 's/port \".*\"/port \"9999\"/g' /fluentd/etc/fluent.conf"

echo "2. Restarting Fluentd to apply UDP configuration change..."
docker exec fluentd-snmp-trap sh -c "pkill -f fluentd || true; sleep 2; fluentd -c /fluentd/etc/fluent.conf -p /fluentd/plugins &"
sleep 5

echo "3. Sending test SNMP trap during UDP endpoint unavailability..."
TEST_ID_2="${TEST_PREFIX}UDP-DOWN-$(date +%s)"
docker exec fluentd-snmp-trap snmptrap -v 3 \
  -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID_2"

echo "4. Waiting for processing (15s)..."
sleep 15

echo "5. Restoring UDP endpoint configuration..."
docker exec fluentd-snmp-trap sh -c "sed -i 's/host \".*\"/host \"$ORIG_UDP_HOST\"/g' /fluentd/etc/fluent.conf"
docker exec fluentd-snmp-trap sh -c "sed -i 's/port \".*\"/port \"$ORIG_UDP_PORT\"/g' /fluentd/etc/fluent.conf"

echo "6. Restarting Fluentd with original configuration..."
docker exec fluentd-snmp-trap sh -c "pkill -f fluentd || true; sleep 2; fluentd -c /fluentd/etc/fluent.conf -p /fluentd/plugins &"
sleep 5

# Test 3: Both Destinations Unavailable
echo "=== Test 3: Both Destinations Unavailable ==="
echo "1. Disconnecting Kafka and redirecting UDP..."
docker network disconnect $KAFKA_NETWORK kafka
docker exec fluentd-snmp-trap sh -c "sed -i 's/host \".*\"/host \"1.2.3.4\"/g' /fluentd/etc/fluent.conf"
docker exec fluentd-snmp-trap sh -c "sed -i 's/port \".*\"/port \"9999\"/g' /fluentd/etc/fluent.conf"

echo "2. Restarting Fluentd to apply configuration..."
docker exec fluentd-snmp-trap sh -c "pkill -f fluentd || true; sleep 2; fluentd -c /fluentd/etc/fluent.conf -p /fluentd/plugins &"
sleep 5

echo "3. Sending test SNMP trap during complete outage..."
TEST_ID_3="${TEST_PREFIX}ALL-DOWN-$(date +%s)"
docker exec fluentd-snmp-trap snmptrap -v 3 \
  -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID_3"

echo "4. Waiting for buffer retry attempts (15s)..."
sleep 15

echo "5. Checking buffer files during outage..."
docker exec fluentd-snmp-trap ls -la /fluentd/buffer/kafka /fluentd/buffer/error 2>/dev/null || echo "No buffer files found"

echo "6. Checking for error logs..."
docker exec fluentd-snmp-trap ls -la /fluentd/log || echo "No log directory found"

echo "7. Restoring all services..."
docker network connect $KAFKA_NETWORK kafka
docker exec fluentd-snmp-trap sh -c "sed -i 's/host \".*\"/host \"$ORIG_UDP_HOST\"/g' /fluentd/etc/fluent.conf"
docker exec fluentd-snmp-trap sh -c "sed -i 's/port \".*\"/port \"$ORIG_UDP_PORT\"/g' /fluentd/etc/fluent.conf"

echo "8. Restarting Fluentd with original configuration..."
docker exec fluentd-snmp-trap sh -c "pkill -f fluentd || true; sleep 2; fluentd -c /fluentd/etc/fluent.conf -p /fluentd/plugins &"
sleep 5

# Wait for buffer flush
echo "9. Waiting for buffer flush after service restoration (30s)..."
sleep 30

# Check reception of all traps
echo "=== Checking Trap Reception ==="
echo "1. Verifying snmptrapd received all traps..."
FINAL_COUNT=$(docker exec fluentd-snmp-trap grep -c "SNMPTRAP:" /var/log/snmptrapd.log || echo 0)
TRAPS_RECEIVED=$((FINAL_COUNT - BASELINE_COUNT))
echo "New traps received: $TRAPS_RECEIVED (should be 3)"

for TEST_ID in "$TEST_ID_1" "$TEST_ID_2" "$TEST_ID_3"; do
  if docker exec fluentd-snmp-trap grep -q "$TEST_ID" /var/log/snmptrapd.log; then
    echo "✅ $TEST_ID was received by snmptrapd"
  else
    echo "❌ $TEST_ID was NOT received by snmptrapd"
  fi
done

# Check Kafka for test messages
echo "2. Checking Kafka output after service restoration..."
docker exec kafka sh -c "kafka-console-consumer --bootstrap-server localhost:9092 --topic snmp_traps --from-beginning --max-messages 100 > /tmp/kafka_chaos_output.txt"
docker exec kafka cat /tmp/kafka_chaos_output.txt > "$TEMP_DIR/kafka_data.txt"

for TEST_ID in "$TEST_ID_1" "$TEST_ID_2" "$TEST_ID_3"; do
  if grep -q "$TEST_ID" "$TEMP_DIR/kafka_data.txt"; then
    echo "✅ $TEST_ID was successfully delivered to Kafka after recovery"
  else
    echo "❓ $TEST_ID was not found in Kafka (might still be in retry buffer)"
  fi
done

# Check Error Logs
echo "3. Checking error logs..."
if docker exec fluentd-snmp-trap [ -d "/fluentd/log" ] && docker exec fluentd-snmp-trap ls -la /fluentd/log | grep -q "error_"; then
  echo "⚠️ Error logs found (expected during outage)"
  docker exec fluentd-snmp-trap cat /fluentd/log/error_*.log | tail -n 10
else
  echo "No error logs found"
fi

# Check buffer status
echo "4. Checking final buffer status..."
docker exec fluentd-snmp-trap ls -la /fluentd/buffer/kafka /fluentd/buffer/error 2>/dev/null || echo "No buffer files found"

# Summary
echo 
echo "=== Chaos Test Summary ==="
echo "Test 1 (Kafka Outage): $(docker exec fluentd-snmp-trap grep -q "$TEST_ID_1" /var/log/snmptrapd.log && echo TRAP_RECEIVED || echo TRAP_MISSING)"
echo "Test 2 (UDP Outage): $(docker exec fluentd-snmp-trap grep -q "$TEST_ID_2" /var/log/snmptrapd.log && echo TRAP_RECEIVED || echo TRAP_MISSING)"
echo "Test 3 (Both Down): $(docker exec fluentd-snmp-trap grep -q "$TEST_ID_3" /var/log/snmptrapd.log && echo TRAP_RECEIVED || echo TRAP_MISSING)"
echo
echo "Kafka delivery: $(grep -q "$TEST_ID_1" "$TEMP_DIR/kafka_data.txt" && echo "✅" || echo "❌") $TEST_ID_1"
echo "Kafka delivery: $(grep -q "$TEST_ID_2" "$TEMP_DIR/kafka_data.txt" && echo "✅" || echo "❌") $TEST_ID_2"
echo "Kafka delivery: $(grep -q "$TEST_ID_3" "$TEMP_DIR/kafka_data.txt" && echo "✅" || echo "❌") $TEST_ID_3"
echo
echo "=== Test Completed ==="

# Clean up
rm -rf "$TEMP_DIR" 