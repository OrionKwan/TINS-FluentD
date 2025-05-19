#!/bin/bash
# Test script to generate SNMPv3 traps with different engine IDs

# Default target
TARGET="localhost:1162"
USER="NCEadmin"
AUTH_PASS="P@ssw0rdauth"
PRIV_PASS="P@ssw0rddata"

echo "=== SNMPv3 Engine ID Test Generator ==="

# Array of test Engine IDs
ENGINE_IDS=(
  "0x8000000001020304"  # Generic test ID
  "0x80001F88807C0F9A615F4B0768"  # Example from logs
  "0x80001F88012345678"  # Another example format
  "0x80000000c001c0a8010a"  # IP-based format
)

echo "Will send SNMPv3 traps with the following Engine IDs:"
for id in "${ENGINE_IDS[@]}"; do
  echo " - $id"
done
echo

# Function to send a trap with specific engine ID
send_trap() {
  local engine_id=$1
  local test_id="TEST-$(date +%s)"
  
  echo "Sending SNMPv3 trap with Engine ID: $engine_id"
  echo "Test ID: $test_id"
  
  # Send the trap
  snmptrap -v 3 -e "$engine_id" -u "$USER" -a MD5 -A "$AUTH_PASS" -x DES -X "$PRIV_PASS" \
    -l authPriv "$TARGET" '' \
    1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$test_id"
    
  echo "Trap sent at $(date +"%Y-%m-%d %H:%M:%S")"
  echo "--------------------------------------"
  
  # Wait between traps
  sleep 2
}

# Send traps with each engine ID
for id in "${ENGINE_IDS[@]}"; do
  send_trap "$id"
done

echo "All test traps sent. Check monitor output for results." 