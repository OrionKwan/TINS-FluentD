#!/bin/bash
# Script to diagnose UDP forwarding issues

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
TEST_ID="UDP-TEST-$(date +%s)"

# Print test header
echo "============================================================"
echo "  UDP Forwarding Diagnostic Test"
echo "============================================================"
echo "UDP Output:  $UDP_HOST:$UDP_PORT"
echo "Test ID:     $TEST_ID"
echo "Date/Time:   $(date)"
echo "============================================================"
echo ""

# Step 1: Send a direct UDP message from host
log_info "Sending direct UDP message from host..."
echo "<test><timestamp>$(date)</timestamp><id>$TEST_ID-DIRECT</id></test>" | nc -u -w1 $UDP_HOST $UDP_PORT
if [ $? -eq 0 ]; then
  log_success "Direct UDP test message sent successfully from host"
else
  log_error "Failed to send direct UDP test message from host"
fi

# Step 2: Send a direct UDP message from container
log_info "Sending direct UDP message from container..."
CONTAINER_CMD="echo '<test><timestamp>$(date)</timestamp><id>$TEST_ID-CONTAINER</id></test>' | nc -u -w1 $UDP_HOST $UDP_PORT"
docker exec fluentd-snmp-trap sh -c "$CONTAINER_CMD"
if [ $? -eq 0 ]; then
  log_success "Direct UDP test message sent successfully from container"
else
  log_error "Failed to send direct UDP test message from container"
fi

# Step 3: Test using Ruby Socket directly (like Fluentd does)
log_info "Testing with Ruby UDP socket from container (Fluentd method)..."
RUBY_CMD="require 'socket'; s=UDPSocket.new; s.send('<test><ruby><timestamp>#{Time.now}</timestamp><id>$TEST_ID-RUBY</id></ruby></test>', 0, '$UDP_HOST', $UDP_PORT); puts 'Ruby UDP test sent successfully'"
docker exec fluentd-snmp-trap ruby -e "$RUBY_CMD" 2>/dev/null
if [ $? -eq 0 ]; then
  log_success "Ruby UDP socket test sent successfully from container"
else
  log_error "Failed to send Ruby UDP socket test from container"
fi

# Step 4: Check for permission/firewall issues
log_info "Checking container networking capabilities..."

# Check if container can reach the UDP host
docker exec fluentd-snmp-trap ping -c 2 $UDP_HOST > /dev/null 2>&1
if [ $? -eq 0 ]; then
  log_success "Container can ping UDP destination host"
else
  log_warning "Container cannot ping UDP destination host"
  log_info "This could be due to ICMP being blocked or network configuration"
fi

# Check network interfaces
log_info "Container network interfaces:"
docker exec fluentd-snmp-trap ip route
docker exec fluentd-snmp-trap ip addr show | grep -E "inet |eth"

# Check iptables rules in container
log_info "Checking iptables rules in container:"
docker exec fluentd-snmp-trap iptables -L 2>/dev/null || log_info "iptables not available in container"

# Step 5: Check Fluentd UDP plugin installation and configuration
log_info "Checking Fluentd UDP plugin installation..."
PLUGIN_INFO=$(docker exec fluentd-snmp-trap gem list | grep fluent-plugin-udp)
if [ -n "$PLUGIN_INFO" ]; then
  log_success "UDP plugin is installed: $PLUGIN_INFO"
else
  log_error "UDP plugin is not installed!"
  log_info "Fluentd installed gems:"
  docker exec fluentd-snmp-trap gem list | grep fluent-plugin
fi

# Check Fluentd config
log_info "Checking Fluentd UDP output configuration:"
docker exec fluentd-snmp-trap cat /fluentd/etc/fluent.conf | grep -A 15 "@type udp" | grep -v "^#"

# Step 6: Send an SNMP trap and check Fluentd logs
log_info "Sending a test SNMP trap and checking Fluentd processing..."
ENGINE_ID="0x80001F88807C0F9A615F4B0768000000"
USERNAME="NCEadmin"
AUTH_PROTOCOL="MD5"
AUTH_PASSWORD="P@ssw0rdauth"
PRIV_PROTOCOL="AES"
PRIV_PASSWORD="P@ssw0rddata"
TRAP_DESTINATION="localhost"
TRAP_PORT="1162"

# Send the trap
snmptrap -v 3 -e $ENGINE_ID -u $USERNAME -a $AUTH_PROTOCOL -A $AUTH_PASSWORD \
  -x $PRIV_PROTOCOL -X $PRIV_PASSWORD -l authPriv $TRAP_DESTINATION:$TRAP_PORT '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID-FLUENTD" 2>/dev/null

# Wait a few seconds for processing
log_info "Waiting for trap processing..."
sleep 5

# Check Fluentd logs
log_info "Checking Fluentd logs for UDP output activity..."
docker logs fluentd-snmp-trap --tail 50 | grep -i -E "udp|socket|out_udp"

# Summary
echo ""
echo "============================================================"
echo "  UDP Forwarding Diagnostic Summary"
echo "============================================================"
echo "Test ID: $TEST_ID"
echo "Date/Time: $(date)"
echo ""

# Provide possible solutions
echo "Possible solutions for UDP forwarding issues:"
echo "1. Check if your network allows outbound UDP traffic from Docker containers"
echo "2. Verify that Fluentd is correctly processing the SNMP traps"
echo "3. Try adding buffer configuration to the UDP output:"
echo ""
echo "<buffer>"
echo "  @type memory"
echo "  flush_interval 1s"
echo "  retry_max_times 5"
echo "  retry_wait 1s"
echo "</buffer>"
echo ""
echo "4. Check if the UDP plugin is compatible with your Fluentd version"
echo "5. Consider using a different UDP output plugin or mechanism"

echo "============================================================" 