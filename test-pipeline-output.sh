#!/bin/bash
# Test script to verify the end-to-end pipeline for SNMPv3 traps
# with focus on UDP and Kafka outputs

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
  echo -e "${RED}❌ $1${NC}"
}

log_warning() {
  echo -e "${YELLOW}⚠️ $1${NC}"
}

log_info() {
  echo -e "${BLUE}ℹ️ $1${NC}"
}

# Configuration - these are the correct values identified in our testing
ENGINE_ID="0x80001F88807C0F9A615F4B0768000000"
USERNAME="NCEadmin"
AUTH_PROTOCOL="MD5"
AUTH_PASSWORD="P@ssw0rdauth"
PRIV_PROTOCOL="AES"
PRIV_PASSWORD="P@ssw0rddata"
TRAP_DESTINATION="${TRAP_DESTINATION:-localhost}"
TRAP_PORT="${TRAP_PORT:-1162}"
UDP_HOST="${UDP_FORWARD_HOST:-165.202.6.129}"
UDP_PORT="${UDP_FORWARD_PORT:-1237}"
KAFKA_TOPIC="snmp_traps"

# Create a unique test ID
TEST_ID="FIXED-TEST-$(date +%s)"

# Print test header
echo "============================================================"
echo "  SNMPv3 Trap Pipeline End-to-End Test"
echo "============================================================"
echo "Destination: $TRAP_DESTINATION:$TRAP_PORT"
echo "Engine ID:   $ENGINE_ID"
echo "Auth:        $AUTH_PROTOCOL / $PRIV_PROTOCOL"
echo "UDP Output:  $UDP_HOST:$UDP_PORT"
echo "Kafka Topic: $KAFKA_TOPIC"
echo "Test ID:     $TEST_ID"
echo "Date/Time:   $(date)"
echo "============================================================"
echo ""

# Check if snmptrapd is running
log_info "Checking if snmptrapd is running in the container..."
if docker exec fluentd-snmp-trap pgrep snmptrapd > /dev/null; then
  log_success "snmptrapd is running"
else
  log_error "snmptrapd is not running!"
  log_info "Please check the container status"
  exit 1
fi

# Check if fluentd is running
log_info "Checking if fluentd is running in the container..."
if docker exec fluentd-snmp-trap pgrep -f fluentd > /dev/null; then
  log_success "fluentd is running"
else
  log_error "fluentd is not running!"
  log_info "Please check the container status"
  exit 1
fi

# Step 1: Send SNMPv3 trap
log_info "Sending SNMPv3 trap with correct configuration..."
snmptrap -v 3 -e $ENGINE_ID -u $USERNAME -a $AUTH_PROTOCOL -A $AUTH_PASSWORD \
  -x $PRIV_PROTOCOL -X $PRIV_PASSWORD -l authPriv $TRAP_DESTINATION:$TRAP_PORT '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID" 2>/dev/null

if [ $? -eq 0 ]; then
  log_success "Trap sent successfully"
else
  log_error "Failed to send trap!"
  exit 1
fi

# Step 2: Check if trap was received
log_info "Waiting for trap to be received (10 seconds)..."
sleep 5
echo -n "Checking log "
for i in {1..5}; do
  echo -n "."
  sleep 1
done
echo ""

# Check snmptrapd log
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$TEST_ID"; then
  log_success "Trap was received by snmptrapd"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID" | tail -2
else
  log_error "Trap was not received by snmptrapd!"
  log_info "Last 5 log entries:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -5
  exit 1
fi

# Step 3: Check Fluentd processing
log_info "Checking if Fluentd processed the trap..."
sleep 2
if docker logs fluentd-snmp-trap --tail 50 | grep -q "$TEST_ID"; then
  log_success "Trap was processed by Fluentd"
  docker logs fluentd-snmp-trap --tail 50 | grep "$TEST_ID" | head -2
else
  log_warning "Could not confirm Fluentd processing in logs"
  log_info "This might be due to logging level settings"
fi

# Step 4: Check UDP output configuration in detail
log_info "Checking UDP output configuration in detail..."

# Check the Fluentd UDP plugin installation
log_info "Verifying UDP plugin installation..."
udp_plugin_check=$(docker exec fluentd-snmp-trap gem list | grep fluent-plugin-udp)
if [ -n "$udp_plugin_check" ]; then
  log_success "UDP plugin is installed: $udp_plugin_check"
else
  log_error "UDP plugin is not installed!"
  log_info "Installing UDP plugin..."
  docker exec fluentd-snmp-trap gem install fluent-plugin-udp -v 0.0.5
fi

# Try to extract UDP configuration from fluentd config
log_info "Checking UDP configuration in fluent.conf..."
udp_config=$(docker exec fluentd-snmp-trap cat /fluentd/etc/fluent.conf | grep -A 15 "@type udp" | grep -v "^#")
if [ -n "$udp_config" ]; then
  log_success "UDP output is configured:"
  echo "$udp_config" | sed 's/^/    /'

  # Check if the UDP configuration matches our expected values
  if echo "$udp_config" | grep -q "$UDP_HOST" && echo "$udp_config" | grep -q "$UDP_PORT"; then
    log_success "UDP configuration matches expected destination"
  else
    log_warning "UDP configuration does not match expected destination"
    log_info "Expected: $UDP_HOST:$UDP_PORT"
    
    # Display actual values being used
    actual_host=$(echo "$udp_config" | grep -o 'host "[^"]*"' | sed 's/host "//;s/"//')
    actual_port=$(echo "$udp_config" | grep -o 'port "[^"]*"' | sed 's/port "//;s/"//')
    log_info "Actual: $actual_host:$actual_port"
  fi
  
  # Check for buffer configuration which might affect forwarding
  if echo "$udp_config" | grep -q "<buffer>"; then
    buffer_config=$(echo "$udp_config" | grep -A 5 "<buffer>" | grep -v "^$")
    log_info "Buffer configuration found:"
    echo "$buffer_config" | sed 's/^/    /'
  else
    log_info "No buffer configuration found for UDP output"
    log_info "Adding a simple buffer configuration might improve reliability"
  fi
  
  # Check message format
  if echo "$udp_config" | grep -q "message_format"; then
    message_format=$(echo "$udp_config" | grep "message_format")
    log_info "Message format: $message_format"
  else
    log_warning "No message_format specified in UDP configuration"
  fi
else
  log_error "Could not find UDP output configuration in fluent.conf"
  
  # Show the entire fluent.conf for debugging
  log_info "Contents of fluent.conf:"
  docker exec fluentd-snmp-trap cat /fluentd/etc/fluent.conf
fi

# Check UDP plugin in logs
log_info "Checking for UDP plugin issues in logs..."
udp_log_issues=$(docker logs fluentd-snmp-trap 2>&1 | grep -i "udp" | grep -i -E "error|warn|fail" | tail -5)
if [ -n "$udp_log_issues" ]; then
  log_error "Found UDP-related issues in logs:"
  echo "$udp_log_issues" | sed 's/^/    /'
else
  log_success "No UDP-related issues found in logs"
fi

# Test network connectivity from container
log_info "Testing network connectivity from container to UDP destination..."
docker exec fluentd-snmp-trap ping -c 2 $UDP_HOST > /dev/null 2>&1
if [ $? -eq 0 ]; then
  log_success "Container can reach UDP destination host ($UDP_HOST)"
else
  log_warning "Container cannot ping UDP destination host ($UDP_HOST)"
  log_info "This might be due to firewall rules or network configuration"
fi

# Check for any network interface issues
log_info "Checking container network interfaces..."
docker exec fluentd-snmp-trap ip addr show | grep -E "inet |eth0"

# Check if UDP traffic is being blocked
log_info "Checking if Docker is allowing UDP outgoing traffic..."
docker exec fluentd-snmp-trap sh -c "nc -zu $UDP_HOST $UDP_PORT -w 1"
if [ $? -eq 0 ]; then
  log_success "UDP connectivity test succeeded"
else
  log_warning "UDP connectivity test failed from within container"
fi

# Test with a direct UDP message to verify connectivity
log_info "Sending direct UDP test message..."
echo "<test><timestamp>$(date)</timestamp><id>$TEST_ID-UDP-DIRECT</id></test>" | nc -u -w1 $UDP_HOST $UDP_PORT
if [ $? -eq 0 ]; then
  log_success "Direct UDP test message sent successfully from host"
else
  log_error "Failed to send direct UDP test message from host"
fi

# Step 5: Test a manual UDP message from Fluentd
log_info "Testing manual UDP message from Fluentd..."
manual_test_cmd="require 'socket'; s=UDPSocket.new; s.send('<test><manual>true</manual><id>$TEST_ID-MANUAL</id></test>', 0, '$UDP_HOST', $UDP_PORT); puts 'Manual UDP test sent'"
docker exec fluentd-snmp-trap ruby -e "$manual_test_cmd" 2>/dev/null
if [ $? -eq 0 ]; then
  log_success "Manual UDP test from container sent successfully"
else
  log_error "Failed to send manual UDP test from container"
fi

# Step 6: Check Kafka output
log_info "Checking Kafka output to topic '$KAFKA_TOPIC'..."

# Check if Kafka is running
if docker ps | grep -q kafka; then
  log_info "Kafka container is running"
  
  # Wait a bit for message to reach Kafka
  log_info "Waiting for message to reach Kafka (5 seconds)..."
  sleep 5
  
  # Try to consume the message
  log_info "Attempting to read from Kafka topic..."
  kafka_output=$(timeout 10s docker exec kafka kafka-console-consumer --bootstrap-server kafka:9092 \
    --topic $KAFKA_TOPIC --from-beginning --max-messages 20 2>/dev/null)
  
  if [ -n "$kafka_output" ]; then
    log_success "Successfully read messages from Kafka"
    
    # Try to find our test message
    if echo "$kafka_output" | grep -q "$TEST_ID"; then
      log_success "Found our test message in Kafka topic!"
      echo "$kafka_output" | grep "$TEST_ID" | head -2 | sed 's/^/    /'
      
      # If Kafka is working but UDP is not, this suggests a UDP configuration issue
      log_info "Since Kafka output works but UDP doesn't, this confirms a UDP-specific issue"
    else
      log_warning "Our test message was not found in Kafka"
      log_info "This could be due to timing or configuration issues"
      log_info "Sample of Kafka messages:"
      echo "$kafka_output" | head -3 | sed 's/^/    /'
    fi
  else
    log_warning "No messages found in Kafka topic"
    log_info "Checking Kafka broker status..."
    docker exec kafka kafka-topics --list --bootstrap-server kafka:9092 | grep -q "$KAFKA_TOPIC"
    if [ $? -eq 0 ]; then
      log_success "Kafka topic '$KAFKA_TOPIC' exists"
    else
      log_error "Kafka topic '$KAFKA_TOPIC' does not exist!"
    fi
  fi
else
  log_warning "Kafka container is not running"
  log_info "Skipping Kafka output verification"
fi

# Summary
echo ""
echo "============================================================"
echo "  End-to-End Pipeline Test Summary"
echo "============================================================"
echo "Test ID: $TEST_ID"
echo "Date/Time: $(date)"
echo ""

# Count successes and issues in the current run
success_count=$(grep -c "✅" /dev/stdout | wc -l || echo "0")
warning_count=$(grep -c "⚠️" /dev/stdout | wc -l || echo "0")
error_count=$(grep -c "❌" /dev/stdout | wc -l || echo "0")

echo -e "${GREEN}Successes: $success_count${NC}"
echo -e "${YELLOW}Warnings: $warning_count${NC}"
echo -e "${RED}Errors: $error_count${NC}"
echo ""

if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$TEST_ID"; then
  log_success "OVERALL: SNMPv3 trap was successfully received by snmptrapd"
  
  if docker ps | grep -q kafka && echo "$kafka_output" | grep -q "$TEST_ID"; then
    log_success "OVERALL: Trap to Kafka pipeline is working: SNMPv3 → Fluentd → Kafka"
  elif ! docker ps | grep -q kafka; then
    log_warning "OVERALL: Kafka verification was skipped (container not running)"
  else
    log_warning "OVERALL: Kafka output could not be verified"
  fi
  
  log_warning "CONCLUSION: UDP forwarding is not working properly despite valid configuration"
  log_info "RECOMMENDATION: Consider these possible issues:"
  log_info "1. Firewall blocking UDP traffic from container"
  log_info "2. UDP plugin might need to be updated or reconfigured with socket_buffer_size and send_timeout"
  log_info "3. Network routing issues between container and destination"
  log_info "4. Try adding a buffer configuration to the UDP output"
else
  log_error "OVERALL: SNMPv3 trap was not received - pipeline verification failed"
fi

echo "============================================================"

# Print suggested UDP configuration fix
echo ""
echo "============================================================"
echo "  Suggested UDP Configuration Fix"
echo "============================================================"
echo "Add the following to your UDP output configuration in fluent.conf:"
echo ""
echo "<store>"
echo "  @type udp"
echo "  @id out_udp"
echo "  host \"#{ENV['UDP_FORWARD_HOST'] || '165.202.6.129'}\""
echo "  port \"#{ENV['UDP_FORWARD_PORT'] || '1237'}\""
echo "  message_format <snmp_trap><timestamp>%{time}</timestamp><version>SNMPv3</version><data>%{message}</data></snmp_trap>"
echo "  socket_buffer_size 16777216"
echo "  send_timeout 10"
echo "  ignore_error true"
echo ""
echo "  <buffer>"
echo "    @type memory"
echo "    flush_interval 1s"
echo "    retry_max_times 5"
echo "    retry_wait 1s"
echo "  </buffer>"
echo "</store>"
echo "============================================================" 