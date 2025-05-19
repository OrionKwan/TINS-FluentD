#!/bin/bash

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

# Configuration values
CONTAINER_NAME="fluentd-snmp-trap"
ENGINE_ID="${ENGINE_ID:-0x80001F88807C0F9A615F4B0768000000}"
USERNAME="${USERNAME:-NCEadmin}"
AUTH_PROTOCOL="${AUTH_PROTOCOL:-MD5}"
AUTH_PASSWORD="${AUTH_PASSWORD:-P@ssw0rdauth}"
PRIV_PROTOCOL="${PRIV_PROTOCOL:-AES}"
PRIV_PASSWORD="${PRIV_PASSWORD:-P@ssw0rddata}"
TRAP_PORT="${TRAP_PORT:-1162}"

echo "============================================================"
echo "  SNMPv3 Trap Configuration Health Check"
echo "============================================================"
echo "Container: $CONTAINER_NAME"
echo "Engine ID: $ENGINE_ID"
echo "Username:  $USERNAME"
echo "Auth:      $AUTH_PROTOCOL / $AUTH_PASSWORD"
echo "Privacy:   $PRIV_PROTOCOL / $PRIV_PASSWORD"
echo "Port:      $TRAP_PORT"
echo "============================================================"
echo ""

# 1. Check if container is running
log_info "Checking if container is running..."
if docker ps | grep -q "$CONTAINER_NAME"; then
  log_success "Container is running"
else
  log_error "Container is not running. Please start the container first."
  exit 1
fi

# 2. Check snmptrapd status in container
log_info "Checking if snmptrapd is running in the container..."
if docker exec $CONTAINER_NAME pgrep snmptrapd > /dev/null; then
  log_success "snmptrapd is running"
else
  log_error "snmptrapd is not running in the container!"
  exit 1
fi

# 3. Check snmptrapd configuration
log_info "Examining snmptrapd configuration..."
conf=$(docker exec $CONTAINER_NAME cat /etc/snmp/snmptrapd.conf 2>/dev/null)

# Check Engine ID in config
if echo "$conf" | grep -q "$ENGINE_ID"; then
  log_success "Engine ID $ENGINE_ID found in configuration"
else
  log_error "Engine ID $ENGINE_ID NOT found in snmptrapd.conf!"
  log_info "Found configuration:"
  echo "$conf" | grep -i "createuser" || echo "No createUser directive found"
fi

# Check username in config
if echo "$conf" | grep -q "$USERNAME"; then
  log_success "Username $USERNAME found in configuration"
else
  log_error "Username $USERNAME NOT found in snmptrapd.conf!"
  log_info "Users defined in configuration:"
  echo "$conf" | grep -i "user" || echo "No user directives found"
fi

# Check for disableAuthorization
if echo "$conf" | grep -q "disableAuthorization yes"; then
  log_success "disableAuthorization directive is set to yes"
else
  log_warning "disableAuthorization directive not set to yes, may reject some traps"
fi

# 4. Check port binding
log_info "Checking port binding..."
port_check=$(docker exec $CONTAINER_NAME netstat -ln | grep ":$TRAP_PORT" || echo "")
if [ -n "$port_check" ]; then
  log_success "Port $TRAP_PORT is bound in container"
else
  log_error "Port $TRAP_PORT is NOT bound in container!"
  log_info "Current port bindings:"
  docker exec $CONTAINER_NAME netstat -ln | grep -E "udp|:16" || echo "No relevant ports found"
fi

# 5. Check log file
log_info "Checking snmptrapd log file..."
if docker exec $CONTAINER_NAME test -f "/var/log/snmptrapd.log"; then
  log_success "Log file exists"
  
  # Check permissions
  perms=$(docker exec $CONTAINER_NAME ls -l /var/log/snmptrapd.log | awk '{print $1}')
  if [[ "$perms" == *"rw"* ]]; then
    log_success "Log file has correct permissions: $perms"
  else
    log_warning "Log file may have incorrect permissions: $perms"
  fi
  
  # Check if log file is being written to
  log_content=$(docker exec $CONTAINER_NAME cat /var/log/snmptrapd.log 2>/dev/null)
  if [ -n "$log_content" ]; then
    log_success "Log file contains content"
    log_info "Last few lines of log:"
    docker exec $CONTAINER_NAME tail -5 /var/log/snmptrapd.log 2>/dev/null || echo "Unable to read log"
  else
    log_warning "Log file is empty - no traps received or logging not working"
  fi
else
  log_error "Log file /var/log/snmptrapd.log does not exist!"
fi

# 6. Test sending a trap and verify reception
log_info "Testing direct trap reception..."
TEST_ID="HEALTH-CHECK-$(date +%s)"

# Send test trap
log_info "Sending SNMPv3 trap with ID: $TEST_ID..."
snmptrap -v 3 -e $ENGINE_ID -u $USERNAME -a $AUTH_PROTOCOL -A "$AUTH_PASSWORD" \
  -x $PRIV_PROTOCOL -X "$PRIV_PASSWORD" -l authPriv localhost:$TRAP_PORT '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID" 2>/dev/null

# Wait briefly for processing
sleep 2

# Check if trap was received
log_info "Checking if trap was received..."
if docker exec $CONTAINER_NAME grep -q "$TEST_ID" /var/log/snmptrapd.log 2>/dev/null; then
  log_success "Trap was received successfully!"
  docker exec $CONTAINER_NAME grep "$TEST_ID" /var/log/snmptrapd.log
else
  log_error "Trap was NOT received!"
  
  # Try running snmptrapd in debug mode for more info
  log_info "Starting a temporary debug snmptrapd for detailed info..."
  docker exec $CONTAINER_NAME pkill snmptrapd 2>/dev/null
  debug_output=$(docker exec $CONTAINER_NAME sh -c "snmptrapd -Dusm,secmod -Le -p /var/run/snmptrapd.pid -f" & sleep 2; docker exec $CONTAINER_NAME pkill snmptrapd)
  echo "$debug_output" | grep -E "usm|secmod|user|trap" | head -20
  
  # Restart the original snmptrapd
  docker exec $CONTAINER_NAME sh -c "snmptrapd -c /etc/snmp/snmptrapd.conf -Lf /var/log/snmptrapd.log -f &"
fi

# 7. Summary
echo ""
echo "============================================================"
echo "  SNMPv3 Health Check Summary"
echo "============================================================"
SUCCESS_COUNT=$(grep -c "✅" /dev/stdout || echo "0")
ERROR_COUNT=$(grep -c "❌" /dev/stdout || echo "0")
WARNING_COUNT=$(grep -c "⚠️" /dev/stdout || echo "0")

echo -e "${GREEN}Successes: $SUCCESS_COUNT${NC}"
echo -e "${RED}Errors: $ERROR_COUNT${NC}"
echo -e "${YELLOW}Warnings: $WARNING_COUNT${NC}"
echo ""

if [ $ERROR_COUNT -gt 0 ]; then
  log_error "Configuration issues detected! Please fix before continuing."
  
  # Provide recommendations
  echo ""
  echo "Recommendations:"
  echo "1. Make sure Engine ID matches exactly between sender and receiver"
  echo "2. Verify auth and encryption protocols match (MD5/SHA and DES/AES)"
  echo "3. Check that snmptrapd is running with the correct permissions"
  echo "4. Ensure the trap port (UDP $TRAP_PORT) is correctly bound"
  echo "5. Check network connectivity between the trap sender and receiver"
elif [ $WARNING_COUNT -gt 0 ]; then
  log_warning "Some potential issues were found, but configuration might still work."
else
  log_success "All checks passed successfully!"
fi
echo "============================================================" 