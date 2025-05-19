#!/bin/bash
# Send test SNMPv3 traps with Engine IDs derived from IP 172.29.36.80

# Configuration
TARGET="localhost:1162"
USER="NCEadmin"
AUTH_PASS="P@ssw0rdauth"
PRIV_PASS="P@ssw0rddata"
DELAY=2

# The IP to convert to engine ID
IP="172.29.36.80"

# Convert IP to hex
ip_hex=""
for octet in $(echo $IP | tr '.' ' '); do
    hex=$(printf "%02X" $octet)
    ip_hex="${ip_hex}${hex}"
done

echo "=== SNMPv3 IP-based Engine ID Test ==="
echo "IP Address: $IP (hex: $ip_hex)"
echo "Target: $TARGET"
echo

# Create array of engine IDs to test
ENGINE_IDS=(
  "0x800000000001${ip_hex}"  # Standard format with default enterprise ID
  "0x800000C00001${ip_hex}"  # Format with Cisco enterprise ID
  "0x80${ip_hex}"            # Format with no enterprise indicator
  "0x8000000001${ip_hex}"    # Format with RFC 3411 compliance
)

# Function to send a trap with specific engine ID
send_trap() {
  local engine_id=$1
  local test_id="IP-TEST-$(date +%s)"
  
  echo "Sending SNMPv3 trap with Engine ID: $engine_id"
  echo "Test ID: $test_id"
  
  # Send the trap with explicit engine ID
  snmptrap -v 3 -e "$engine_id" -u "$USER" -a MD5 -A "$AUTH_PASS" -x DES -X "$PRIV_PASS" \
    -l authPriv "$TARGET" '' \
    1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$test_id"
    
  local status=$?
  if [ $status -eq 0 ]; then
    echo "✓ Trap sent successfully"
  else
    echo "⚠️ Failed to send trap (status $status)"
  fi
  
  echo "--------------------------------------"
  sleep $DELAY
}

# Also try the SNMPv2c version for comparison
echo "Sending SNMPv2c trap for comparison..."
snmptrap -v 2c -c public $TARGET '' 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "V2C-TEST-$(date +%s)"
echo "--------------------------------------"
sleep $DELAY

# Send traps with each engine ID format
for id in "${ENGINE_IDS[@]}"; do
  send_trap "$id"
done

# Try sending a trap with remote IP as destination
echo "Sending direct trap to the remote IP..."
snmptrap -v 3 -e "0x800000000001${ip_hex}" -u "$USER" -a MD5 -A "$AUTH_PASS" -x DES -X "$PRIV_PASS" \
  -l authPriv "$IP:162" '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "DIRECT-TEST-$(date +%s)"

echo
echo "All test traps sent. Use sudo ./extract-engine-id.sh or Wireshark to check results." 