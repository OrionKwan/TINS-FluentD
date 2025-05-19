#!/bin/bash
# Script to generate an IP-based Engine ID for SNMPv3

# The IP address to use (you can change this)
IP_ADDRESS="192.168.1.10"

# Convert the IP address to hex
IP_HEX=$(echo $IP_ADDRESS | awk -F. '{printf "%02x%02x%02x%02x", $1, $2, $3, $4}')

# Create the Engine ID components:
# 0x80 - Format byte (enterprise-specific)
# 000000c0 - Enterprise ID (192 - for cisco, common example)
# 01 - Format type (01 indicates IPv4 address)
# IP_HEX - The IP address in hex

ENGINE_ID="0x80000000c001${IP_HEX}"

echo "========== IP-Based Engine ID Generator =========="
echo "IP Address: $IP_ADDRESS"
echo "IP in Hex: $IP_HEX"
echo "Engine ID: $ENGINE_ID"
echo "=================================================="

# Generate SNMP configuration for both sides
echo
echo "Configuration for sender side:"
echo "----------------------------"
echo "snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \\"
echo "  -l authPriv localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s \"Test-IP-Engine-ID\""

echo
echo "Configuration for receiver side (snmptrapd.conf):"
echo "-------------------------------------------"
echo "createUser -e $ENGINE_ID NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata"
echo "authUser log,execute,net NCEadmin authPriv"
echo "authCommunity log,execute,net public"
echo "disableAuthorization yes"
echo "traphandle default /usr/local/bin/format-trap.sh"

# Create the configuration files
echo
echo "Creating configuration files..."

# Receiver configuration
cat > receiver-ip-engine.conf << EOF
# SNMPv3 configuration with IP-based Engine ID: $IP_ADDRESS
createUser -e $ENGINE_ID NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata
authUser log,execute,net NCEadmin authPriv
authCommunity log,execute,net public
disableAuthorization yes
traphandle default /usr/local/bin/format-trap.sh
EOF

# Sender test script
cat > test-ip-engine.sh << EOF
#!/bin/bash
# Test script for IP-based Engine ID: $ENGINE_ID

TEST_ID="IP-ENGINE-\$(date +%s)"

echo "=== Testing SNMPv3 with IP-Based Engine ID ==="
echo "IP Address: $IP_ADDRESS"
echo "Engine ID: $ENGINE_ID"
echo "Test ID: \$TEST_ID"
echo

echo "Sending SNMPv3 trap with IP-based Engine ID..."
snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \\
  -l authPriv localhost:1162 '' \\
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "\$TEST_ID" 2>/dev/null

echo "Trap sent. Waiting for processing..."
sleep 2

echo "Checking if trap was received..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "\$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap with IP-based Engine ID was received!"
  echo "Log entry:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "\$TEST_ID"
else
  echo "❌ FAIL: SNMPv3 trap was not received."
  echo "Last 5 log entries:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5
fi

# Also test V2C as a fallback
echo
echo "Testing SNMPv2c trap (fallback)..."
V2C_TEST_ID="V2C-FALLBACK-\$(date +%s)"
snmptrap -v 2c -c public localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 \\
  1.3.6.1.2.1.1.3.0 s "\$V2C_TEST_ID" 2>/dev/null

sleep 2
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "\$V2C_TEST_ID"; then
  echo "✅ SNMPv2c trap was received!"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "\$V2C_TEST_ID"
else
  echo "❌ SNMPv2c trap was not received either."
fi

echo
echo "Testing direct UDP forwarding to 165.202.6.129:1237..."
echo "<snmp_trap><timestamp>\$(date)</timestamp><engineID>$ENGINE_ID</engineID><id>\$TEST_ID-DIRECT</id></snmp_trap>" | nc -u 165.202.6.129 1237
echo "✅ Direct UDP message sent to 165.202.6.129:1237"
EOF

chmod +x test-ip-engine.sh

echo
echo "Files created:"
echo "1. receiver-ip-engine.conf - Configuration for the receiver (container)"
echo "2. test-ip-engine.sh - Test script for sending SNMPv3 traps with IP-based Engine ID"
echo
echo "To apply the configuration and test:"
echo "1. cat receiver-ip-engine.conf | docker exec -i fluentd-snmp-trap tee /etc/snmp/snmptrapd.conf"
echo "2. docker-compose restart fluentd-snmp"
echo "3. ./test-ip-engine.sh" 