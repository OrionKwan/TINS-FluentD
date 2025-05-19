#!/bin/bash
# Script to send UDP test messages directly

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

# Configuration
UDP_HOST="${UDP_FORWARD_HOST:-165.202.6.129}"
UDP_PORT="${UDP_FORWARD_PORT:-1237}"
TEST_ID="UDP-DIRECT-TEST-$(date +%s)"

# Print test header
echo "============================================================"
echo "  UDP Direct Test"
echo "============================================================"
echo "UDP Output:  $UDP_HOST:$UDP_PORT"
echo "Test ID:     $TEST_ID"
echo "Date/Time:   $(date)"
echo "============================================================"
echo ""

# Function to send a UDP message
send_udp_message() {
  local message="$1"
  local retries=${2:-3}
  local success=false
  
  for ((i=1; i<=retries; i++)); do
    log_info "Attempt $i: Sending message..."
    echo "$message" | nc -u -w1 $UDP_HOST $UDP_PORT
    
    if [ $? -eq 0 ]; then
      log_success "Message sent successfully!"
      success=true
      break
    else
      log_warning "Failed to send message (attempt $i of $retries)"
      sleep 1
    fi
  done
  
  if [ "$success" = false ]; then
    log_error "Failed to send message after $retries attempts"
    return 1
  fi
  
  return 0
}

# Send a basic UDP message
log_info "Sending basic UDP message..."
send_udp_message "<test><basic>true</basic><id>${TEST_ID}-BASIC</id></test>"

# Send an SNMPv3 trap-like UDP message
log_info "Sending SNMPv3 trap-like UDP message..."
send_udp_message "<snmp_trap><timestamp>$(date)</timestamp><version>SNMPv3</version><id>${TEST_ID}-TRAP</id><data>DISMAN-EVENT-MIB::sysUpTimeInstance</data></snmp_trap>"

# Send a more complex UDP message
log_info "Sending complex UDP message..."
COMPLEX_MESSAGE="<snmp_trap>
  <timestamp>$(date)</timestamp>
  <version>SNMPv3</version>
  <device>test-device</device>
  <type>coldStart</type>
  <id>${TEST_ID}-COMPLEX</id>
  <data>
    <oid>1.3.6.1.6.3.1.1.5.1</oid>
    <value>Test data with complex structure</value>
  </data>
</snmp_trap>"
send_udp_message "$COMPLEX_MESSAGE"

# Send a simulated Fluentd message
log_info "Sending simulated Fluentd message format..."
FLUENTD_FORMAT="<snmp_trap><timestamp>$(date)</timestamp><version>SNMPv3</version><data>SNMPTRAP: $(date) DISMAN-EVENT-MIB::sysUpTimeInstance \"${TEST_ID}-FLUENTD\"</data></snmp_trap>"
send_udp_message "$FLUENTD_FORMAT"

# Summary
echo ""
echo "============================================================"
echo "  UDP Direct Test Summary"
echo "============================================================"
echo "Test ID: $TEST_ID"
echo "Date/Time: $(date)"
echo ""
log_info "All UDP test messages have been sent to $UDP_HOST:$UDP_PORT"
log_info "Check your UDP receiver to verify if they were received"

echo "============================================================" 