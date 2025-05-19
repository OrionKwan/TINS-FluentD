#!/bin/bash
# Test script for the fixed Fluentd SNMP UDP Forwarding Container

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
DOCKER_NETWORK="mvp-setup_opensearch-net"

# Create a unique test ID
TEST_ID="FIXED-TEST-$(date +%s)"

# Print test header
echo "============================================================"
echo "  Fixed Fluentd SNMP Trap Container Test"
echo "============================================================"
echo "Destination: $TRAP_DESTINATION:$TRAP_PORT"
echo "Engine ID:   $ENGINE_ID"
echo "Auth:        $AUTH_PROTOCOL / $PRIV_PROTOCOL"
echo "UDP Output:  $UDP_HOST:$UDP_PORT"
echo "Kafka Topic: $KAFKA_TOPIC"
echo "Docker Network: $DOCKER_NETWORK"
echo "Test ID:     $TEST_ID"
echo "Date/Time:   $(date)"
echo "============================================================"
echo ""

# Function to run the fixed container
run_fixed_container() {
  log_info "Stopping any existing fluentd-snmp-trap container..."
  docker stop fluentd-snmp-trap 2>/dev/null || true
  docker rm fluentd-snmp-trap 2>/dev/null || true
  
  log_info "Starting fixed container..."
  docker run -d --name fluentd-snmp-trap \
    -p 1162:1162/udp \
    -e SNMPV3_USER=NCEadmin \
    -e SNMPV3_AUTH_PASS=P@ssw0rdauth \
    -e SNMPV3_PRIV_PASS=P@ssw0rddata \
    -e SNMPV3_AUTH_PROTOCOL=SHA \
    -e SNMPV3_PRIV_PROTOCOL=AES \
    -e SNMPV3_ENGINE_ID=$ENGINE_ID \
    -e KAFKA_BROKER=kafka:9092 \
    -e KAFKA_TOPIC=snmp_traps \
    -e UDP_FORWARD_HOST=$UDP_HOST \
    -e UDP_FORWARD_PORT=$UDP_PORT \
    --network $DOCKER_NETWORK \
    fluentd-snmp-fixed
    
  sleep 10  # Give the container some time to start up
  
  # Check if the container is running
  if docker ps | grep -q fluentd-snmp-trap; then
    log_success "Container started successfully"
    # Print container logs
    log_info "Container logs:"
    docker logs fluentd-snmp-trap | tail -20
    return 0
  else
    log_error "Container failed to start"
    log_info "Container logs:"
    docker logs fluentd-snmp-trap
    return 1
  fi
}

# Function to send test SNMP trap
send_test_trap() {
  log_info "Sending SNMPv3 trap with Engine ID: $ENGINE_ID"
  
  snmptrap -v 3 -e $ENGINE_ID -u $USERNAME -a $AUTH_PROTOCOL -A $AUTH_PASSWORD \
    -x $PRIV_PROTOCOL -X $PRIV_PASSWORD -l authPriv $TRAP_DESTINATION:$TRAP_PORT '' \
    1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID" 2>/dev/null
  
  if [ $? -eq 0 ]; then
    log_success "SNMPv3 trap sent successfully"
    return 0
  else
    log_error "Failed to send SNMPv3 trap"
    return 1
  fi
}

# Function to check if the trap was received
check_trap_received() {
  log_info "Checking if trap was received (waiting 5 seconds)..."
  sleep 5
  
  if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log 2>/dev/null | grep -q "$TEST_ID"; then
    log_success "Trap was received by snmptrapd"
    docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID" | tail -2
    return 0
  else
    log_error "Trap was not received by snmptrapd"
    log_info "Last 10 log entries:"
    docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log 2>/dev/null | tail -10 || echo "No log file found"
    return 1
  fi
}

# Function to check Fluentd processing
check_fluentd_processing() {
  log_info "Checking if Fluentd processed the trap (waiting 5 seconds)..."
  sleep 5
  
  if docker logs fluentd-snmp-trap | grep -q "$TEST_ID"; then
    log_success "Trap was processed by Fluentd"
    docker logs fluentd-snmp-trap | grep "$TEST_ID" | head -3
    return 0
  else
    log_warning "Could not confirm Fluentd processing in logs"
    log_info "This could be due to logging level settings"
    log_info "Last 10 log entries:"
    docker logs fluentd-snmp-trap | tail -10
    return 1
  fi
}

# Main test flow
log_info "Starting test of fixed Fluentd SNMP container..."

# Step 1: Run the fixed container
run_fixed_container
if [ $? -ne 0 ]; then
  log_error "Test aborted: Could not start the fixed container"
  exit 1
fi

# Step 2: Send a test SNMP trap
send_test_trap
if [ $? -ne 0 ]; then
  log_warning "Test continuing: Could not send test trap"
fi

# Step 3: Check if the trap was received
check_trap_received
if [ $? -ne 0 ]; then
  log_warning "Test continuing: Could not verify trap reception"
fi

# Step 4: Check if Fluentd processed the trap
check_fluentd_processing
if [ $? -ne 0 ]; then
  log_warning "Test continuing: Could not verify Fluentd processing"
fi

# Step 5: Summary
echo ""
echo "============================================================"
echo "  Test Summary"
echo "============================================================"
echo "Test ID: $TEST_ID"
echo "Date/Time: $(date)"
echo ""
echo "1. Fixed Container: $(docker ps | grep -q fluentd-snmp-trap && echo "Running" || echo "Not Running")"
echo "2. SNMPv3 Trap Reception: $(docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log 2>/dev/null | grep -q "$TEST_ID" && echo "Success" || echo "Not Verified")"
echo "3. Fluentd Processing: $(docker logs fluentd-snmp-trap | grep -q "$TEST_ID" && echo "Success" || echo "Not Verified")"
echo ""
log_info "To verify UDP output, check your UDP receiver for messages with ID: $TEST_ID"
echo "============================================================" 