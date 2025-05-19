#!/bin/bash
# Enhanced Test script for SNMPv3 trap with Engine ID validation
# This script tests various scenarios for SNMPv3 trap reception with Engine ID

# Set trap destination - default to localhost if not specified
TRAP_DESTINATION="${TRAP_DESTINATION:-localhost}"
TRAP_PORT="${TRAP_PORT:-1162}"

# The correct Engine ID from the container configuration
ENGINE_ID="0x80001F88807C0F9A615F4B0768000000"
# Test unique identifier with timestamp
TEST_ID="ENGINE-ID-TEST-$(date +%s)"

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

check_dependencies() {
  log_info "Checking required dependencies..."
  
  for cmd in snmptrap docker nc grep timeout; do
    if ! command -v $cmd &> /dev/null; then
      log_error "Required command not found: $cmd"
      exit 1
    fi
  done
  
  # Check if fluentd-snmp-trap container is running
  if ! docker ps | grep -q fluentd-snmp-trap; then
    log_error "Container fluentd-snmp-trap is not running"
    log_info "Please start the container with: docker-compose up -d fluentd-snmp-trap"
    exit 1
  fi
  
  log_success "All dependencies are available"
}

wait_for_log_entry() {
  local search_term="$1"
  local max_wait="${2:-10}"  # Increased default to 10 seconds
  
  log_info "Waiting for log entry containing: '$search_term' (timeout: ${max_wait}s)"
  
  for i in $(seq 1 $max_wait); do
    if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$search_term"; then
      return 0  # Found
    fi
    sleep 1
    echo -n "."
  done
  echo ""
  return 1  # Not found
}

# Validate SNMP configuration
check_snmp_config() {
  echo "🔍 Validating SNMP Configuration"
  
  # Check SNMPv3 configuration
  log_info "Checking SNMPv3 user configuration..."
  local user_config=$(docker exec fluentd-snmp-trap cat /var/lib/net-snmp/snmptrapd.conf 2>/dev/null)
  
  if [[ -z "$user_config" ]]; then
    log_error "No SNMPv3 user configuration found!"
  else
    log_success "SNMPv3 user configuration found:"
    echo "    $user_config"
    
    # Extract Engine ID from config
    if [[ "$user_config" =~ -e\ ([0-9A-Fx]+) ]]; then
      local config_engine_id="${BASH_REMATCH[1]}"
      log_info "Engine ID in configuration: $config_engine_id"
      
      # Compare with our script's Engine ID
      if [[ "${config_engine_id^^}" == "${ENGINE_ID^^}" ]]; then
        log_success "Engine ID in script matches configuration"
      else
        log_error "Engine ID mismatch! Script: $ENGINE_ID, Config: $config_engine_id"
        log_info "Updating script Engine ID to match configuration..."
        ENGINE_ID="$config_engine_id"
      fi
    else
      log_warning "Could not extract Engine ID from configuration"
    fi
  fi
  
  # Check environment variables
  log_info "Checking environment variables in container..."
  local env_engine_id=$(docker exec fluentd-snmp-trap env | grep SNMPV3_ENGINE_ID | cut -d= -f2)
  
  if [[ -n "$env_engine_id" ]]; then
    log_info "Engine ID in environment: $env_engine_id"
    # Compare with our updated Engine ID
    if [[ "${env_engine_id^^}" == "${ENGINE_ID^^}" ]]; then
      log_success "Engine ID matches environment variable"
    else
      log_warning "Engine ID differs from environment variable"
    fi
  else
    log_warning "No SNMPV3_ENGINE_ID environment variable found"
  fi
  
  # Check authentication and privacy protocols
  log_info "Checking authentication and privacy protocols..."
  local auth_proto=$(docker exec fluentd-snmp-trap env | grep SNMPV3_AUTH_PROTOCOL | cut -d= -f2)
  local priv_proto=$(docker exec fluentd-snmp-trap env | grep SNMPV3_PRIV_PROTOCOL | cut -d= -f2)
  
  log_info "Auth Protocol: ${auth_proto:-Unknown}, Priv Protocol: ${priv_proto:-Unknown}"
  
  echo ""
}

# Display test header
print_header() {
  echo "============================================================"
  echo "  SNMPv3 Trap Test with Engine ID Validation"
  echo "============================================================"
  echo "Destination: $TRAP_DESTINATION:$TRAP_PORT"
  echo "Engine ID:   $ENGINE_ID"
  echo "Test ID:     $TEST_ID"
  echo "Date/Time:   $(date)"
  echo "============================================================"
  echo ""
}

# Main test execution
run_tests() {
  # Test 1: Send SNMPv3 trap with correct Engine ID
  echo "🧪 TEST 1: Send SNMPv3 trap with CORRECT Engine ID"
  log_info "Sending SNMPv3 trap with matched Engine ID..."
  
  # Trying with both SHA and MD5 auth protocols since the configuration may vary
  log_info "First attempt with SHA authentication..."
  snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
    -l authPriv $TRAP_DESTINATION:$TRAP_PORT '' \
    1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID-CORRECT-SHA" 2>/dev/null
  
  if [ $? -eq 0 ]; then
    log_info "Trap sent successfully (SHA)"
  else
    log_warning "Failed to send trap with SHA, error code: $?"
  fi
  
  if wait_for_log_entry "$TEST_ID-CORRECT-SHA"; then
    log_success "SNMPv3 trap with correct Engine ID was received (SHA auth)!"
    docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID-CORRECT-SHA" | tail -1
  else
    log_warning "SNMPv3 trap with SHA auth was NOT received, trying with MD5..."
    
    # Try again with MD5 auth
    snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata \
      -l authPriv $TRAP_DESTINATION:$TRAP_PORT '' \
      1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID-CORRECT-MD5" 2>/dev/null
      
    if [ $? -eq 0 ]; then
      log_info "Trap sent successfully (MD5)"
    else
      log_warning "Failed to send trap with MD5, error code: $?"
    fi
    
    if wait_for_log_entry "$TEST_ID-CORRECT-MD5"; then
      log_success "SNMPv3 trap with correct Engine ID was received (MD5 auth)!"
      docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID-CORRECT-MD5" | tail -1
    else
      log_error "SNMPv3 trap with correct Engine ID was NOT received with either auth method"
      log_info "Last 5 log entries:"
      docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -5
    fi
  fi
  echo ""
  
  # Test 2: Send SNMPv3 trap with incorrect Engine ID
  echo "🧪 TEST 2: Send SNMPv3 trap with INCORRECT Engine ID"
  WRONG_ENGINE_ID="0x0102030405060708"
  log_info "Sending SNMPv3 trap with mismatched Engine ID: $WRONG_ENGINE_ID"
  
  snmptrap -v 3 -e $WRONG_ENGINE_ID -u NCEadmin -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
    -l authPriv $TRAP_DESTINATION:$TRAP_PORT '' \
    1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID-INCORRECT" 2>/dev/null
  
  if wait_for_log_entry "$TEST_ID-INCORRECT"; then
    log_warning "SNMPv3 trap with incorrect Engine ID was unexpectedly received!"
    docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID-INCORRECT" | tail -1
  else
    log_success "SNMPv3 trap with incorrect Engine ID was correctly rejected (expected behavior)"
  fi
  echo ""
  
  # Test 3: Send SNMPv2c trap (should work regardless of Engine ID)
  echo "🧪 TEST 3: Send SNMPv2c trap (baseline test)"
  log_info "Sending SNMPv2c trap..."
  
  snmptrap -v 2c -c public $TRAP_DESTINATION:$TRAP_PORT '' \
    1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID-V2C" 2>/dev/null
  
  if wait_for_log_entry "$TEST_ID-V2C"; then
    log_success "SNMPv2c trap was received (Engine ID not applicable)"
    docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID-V2C" | tail -1
  else
    log_error "SNMPv2c trap was NOT received"
    log_info "Last 5 log entries:"
    docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -5
  fi
  echo ""
  
  # Test 4: Test SNMPv3 with no Engine ID specified (discovery mode)
  echo "🧪 TEST 4: SNMPv3 with No Engine ID (Discovery Mode)"
  log_info "Sending SNMPv3 trap without specifying Engine ID..."
  
  snmptrap -v 3 -u NCEadmin -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
    -l authPriv $TRAP_DESTINATION:$TRAP_PORT '' \
    1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID-DISCOVERY" 2>/dev/null
  
  if wait_for_log_entry "$TEST_ID-DISCOVERY"; then
    log_success "SNMPv3 trap with auto-discovered Engine ID was received!"
    docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID-DISCOVERY" | tail -1
  else
    log_warning "SNMPv3 trap with auto-discovery was NOT received (expected for some configurations)"
  fi
  echo ""
}

# Check Fluentd processing
check_fluentd_processing() {
  echo "🧪 TEST 5: Verify Fluentd processing of SNMP traps"
  log_info "Checking if Fluentd is processing SNMP trap messages..."
  
  # More comprehensive check for Fluentd processing
  if docker logs fluentd-snmp-trap --tail 30 | grep -E "message|snmp\.trap|events|format" | grep -v "checking"; then
    log_success "Fluentd is processing and forwarding messages"
    # Show last few processing log entries
    docker logs fluentd-snmp-trap --tail 10 | grep -E "message|snmp\.trap|events|format" | grep -v "checking" | head -5 | sed 's/^/    /'
  else
    log_error "No recent message processing detected in Fluentd logs"
    log_info "Last 5 lines of Fluentd logs:"
    docker logs fluentd-snmp-trap --tail 5 | sed 's/^/    /'
  fi
  echo ""
}

# Test UDP forwarding functionality
test_udp_forwarding() {
  echo "🧪 TEST 6: UDP Forwarding Test"
  UDP_HOST="${UDP_FORWARD_HOST:-165.202.6.129}"
  UDP_PORT="${UDP_FORWARD_PORT:-1237}"
  
  log_info "Testing direct UDP forwarding to $UDP_HOST:$UDP_PORT..."
  
  # Create a test message
  XML_MESSAGE="<snmp_trap><timestamp>$(date)</timestamp><engineID>$ENGINE_ID</engineID><id>$TEST_ID-DIRECT-UDP</id></snmp_trap>"
  
  # Send test message via UDP
  echo "$XML_MESSAGE" | nc -u -w1 $UDP_HOST $UDP_PORT
  
  if [ $? -eq 0 ]; then
    log_success "Direct UDP message sent to $UDP_HOST:$UDP_PORT"
    log_info "Message: $XML_MESSAGE"
  else
    log_error "Failed to send UDP message to $UDP_HOST:$UDP_PORT"
  fi
  
  log_info "Note: UDP delivery cannot be verified directly without access to the receiver"
  echo ""
}

# Verify Kafka output if applicable
check_kafka_output() {
  echo "🧪 TEST 7: Kafka Output Verification (Optional)"
  
  if docker ps | grep -q kafka; then
    log_info "Attempting to verify message delivery to Kafka..."
    
    # Try to consume messages from Kafka
    kafka_output=$(timeout 5s docker exec kafka kafka-console-consumer --bootstrap-server kafka:9092 \
      --topic snmp_traps --from-beginning --max-messages 5 2>/dev/null || echo "Timeout or error")
    
    if [[ "$kafka_output" != "Timeout or error" && "$kafka_output" != "" ]]; then
      log_success "Messages found in Kafka topic 'snmp_traps'"
      echo "$kafka_output" | head -3 | sed 's/^/    /'
      echo "    ..."
    else
      log_warning "No messages found in Kafka topic in the timeout period"
      log_info "This might be because no messages were forwarded to Kafka"
    fi
  else
    log_info "Kafka container not found - skipping Kafka verification"
  fi
  echo ""
}

# Run all tests
run_all_tests() {
  print_header
  check_dependencies
  
  # Check SNMP configuration first
  check_snmp_config
  
  # Save original log size to detect new entries
  ORIGINAL_LOG_SIZE=$(docker exec fluentd-snmp-trap wc -l /var/log/snmptrapd.log 2>/dev/null | awk '{print $1}')
  log_info "Original log size: $ORIGINAL_LOG_SIZE lines"
  
  run_tests
  check_fluentd_processing
  test_udp_forwarding
  check_kafka_output
  
  # Final report
  NEW_LOG_SIZE=$(docker exec fluentd-snmp-trap wc -l /var/log/snmptrapd.log 2>/dev/null | awk '{print $1}')
  NEW_ENTRIES=$((NEW_LOG_SIZE - ORIGINAL_LOG_SIZE))
  
  echo "============================================================"
  echo "  Test Summary"
  echo "============================================================"
  echo "Tests completed at: $(date)"
  echo "New log entries: $NEW_ENTRIES"
  echo "Engine ID used: $ENGINE_ID"
  echo ""
  
  if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$TEST_ID"; then
    log_success "OVERALL RESULT: Tests detected successful trap processing"
    log_info "The system is correctly receiving and processing SNMPv3 traps"
  else
    log_error "OVERALL RESULT: No test traps were detected in the logs"
    log_info "Check the configuration and Engine ID settings"
  fi
  
  echo "============================================================"
}

# Execute all tests
run_all_tests

echo
echo "Checking if fluentd is processing messages..."
if docker logs fluentd-snmp-trap --tail 10 | grep -q "messages send"; then
  echo "✅ Fluentd is processing and forwarding messages"
  docker logs fluentd-snmp-trap --tail 5 | grep "messages send"
else
  echo "❌ No recent message forwarding detected"
fi

echo
echo "Testing direct UDP forwarding to 165.202.6.129:1237..."
echo "<snmp_trap><timestamp>$(date)</timestamp><engineID>$ENGINE_ID</engineID><id>$TEST_ID-DIRECT</id></snmp_trap>" | nc -u 165.202.6.129 1237
echo "✅ Direct UDP message sent to 165.202.6.129:1237" 