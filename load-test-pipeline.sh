#!/bin/bash
# Load test script for SNMP trap pipeline
# Tests if the pipeline can handle high throughput

echo "=== SNMP Pipeline Load Test ==="
echo "This test will verify that the pipeline can handle high throughput."

# Define constants
ENGINE_ID="0x80001F88807C0F9A615F4B0768000000"
TEST_PREFIX="LOAD-TEST-"
TRAP_COUNT=${1:-1000}  # Default to 1000 traps, can be overridden with first argument
PARALLEL=${2:-10}     # Number of parallel processes, can be overridden with second argument
REPORT_INTERVAL=100   # Report progress every X traps

# Create a temporary directory for test artifacts
echo "Setting up test environment..."
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Ensure the container is running
if ! docker ps | grep -q "fluentd-snmp-trap"; then
  echo "❌ ERROR: Container fluentd-snmp-trap is not running"
  exit 1
fi

# Count existing traps to establish baseline
BASELINE_COUNT=$(docker exec fluentd-snmp-trap grep -c "SNMPTRAP:" /var/log/snmptrapd.log || echo 0)
echo "Baseline trap count: $BASELINE_COUNT"

# Create the load test script
cat > "$TEMP_DIR/send_traps.sh" << EOF
#!/bin/bash
# Arguments: start_index count
start_index=\$1
count=\$2

for ((i=\$start_index; i<\$start_index+\$count; i++)); do
  TEST_ID="${TEST_PREFIX}\$i"
  docker exec fluentd-snmp-trap snmptrap -v 3 \\
    -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth \\
    -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' \\
    1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "\$TEST_ID" > /dev/null 2>&1
  
  # Report progress
  if (( i % $REPORT_INTERVAL == 0 )); then
    echo "Process \$start_index: Sent \$((i-start_index+1)) of \$count traps"
  fi
done
EOF

chmod +x "$TEMP_DIR/send_traps.sh"

# Start load test
echo "Starting load test with $TRAP_COUNT traps across $PARALLEL parallel processes..."
echo "Start time: $(date)"
START_TIME=$(date +%s)

# Launch parallel processes
echo "Launching trap generators..."
for ((p=0; p<PARALLEL; p++)); do
  START_INDEX=$((p * (TRAP_COUNT / PARALLEL) + 1))
  COUNT=$((TRAP_COUNT / PARALLEL))
  "$TEMP_DIR/send_traps.sh" $START_INDEX $COUNT &
  PIDS[$p]=$!
  echo "Started process $p with PID ${PIDS[$p]}, sending traps $START_INDEX to $((START_INDEX+COUNT-1))"
done

# Wait for all processes to complete
echo "Waiting for all trap generators to complete..."
for pid in ${PIDS[*]}; do
  wait $pid
  echo "Process with PID $pid completed"
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo "End time: $(date)"
echo "Duration: $DURATION seconds"

# Give time for processing to complete
echo "Waiting for pipeline processing to complete (30s)..."
sleep 30

# Count final trap count
FINAL_COUNT=$(docker exec fluentd-snmp-trap grep -c "SNMPTRAP:" /var/log/snmptrapd.log || echo 0)
TRAPS_RECEIVED=$((FINAL_COUNT - BASELINE_COUNT))
echo "Final trap count: $FINAL_COUNT"
echo "New traps received: $TRAPS_RECEIVED out of $TRAP_COUNT sent"

# Calculate rate
if [ $DURATION -gt 0 ]; then
  RATE=$(bc <<< "scale=2; $TRAPS_RECEIVED / $DURATION")
  echo "Processing rate: $RATE traps/second"
  
  # Check if meets requirement
  MIN_RATE_REQUIRED=50000  # 50k events/s
  if (( $(bc <<< "$RATE >= $MIN_RATE_REQUIRED") )); then
    echo "✅ SUCCESS: Pipeline exceeds required throughput of 50k events/second"
  else
    echo "⚠️ WARNING: Pipeline throughput of $RATE traps/second is below the required 50k events/second"
  fi
else
  echo "Duration too short to calculate rate"
fi

# Check buffer files
echo "Checking buffer status..."
docker exec fluentd-snmp-trap ls -la /fluentd/buffer/kafka /fluentd/buffer/error 2>/dev/null || echo "No buffer files found (might be normal if flushed)"

# Check for any errors
echo "Checking for errors..."
if docker exec fluentd-snmp-trap ls -la /fluentd/log 2>/dev/null | grep -q "error_"; then
  echo "⚠️ WARNING: Error logs found"
  docker exec fluentd-snmp-trap ls -la /fluentd/log | grep "error_"
  docker exec fluentd-snmp-trap cat /fluentd/log/error_*.log | tail -n 10
else
  echo "✅ No error logs found"
fi

# Check memory usage
echo "Checking memory usage..."
docker stats fluentd-snmp-trap --no-stream --format "table {{.Container}}\t{{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Check buffer files again
echo "Checking final buffer status..."
docker exec fluentd-snmp-trap ls -la /fluentd/buffer/kafka /fluentd/buffer/error 2>/dev/null || echo "No buffer files found (might be normal if flushed)"

# Summary
echo 
echo "=== Load Test Summary ==="
echo "Total traps sent: $TRAP_COUNT"
echo "Total traps received: $TRAPS_RECEIVED"
echo "Success rate: $((TRAPS_RECEIVED * 100 / TRAP_COUNT))%"
echo "Processing rate: $RATE traps/second"
echo
echo "=== Test Completed ==="

# Clean up
rm -rf "$TEMP_DIR" 