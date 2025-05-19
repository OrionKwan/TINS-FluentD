#!/bin/bash
# Script to capture incoming SNMPv3 traps and verify the Engine ID

# Set up the expected Engine ID
IP="172.29.36.80"
IP_HEX=$(printf '%02X%02X%02X%02X' $(echo $IP | tr '.' ' '))
ENGINE_ID="0x80000000c001${IP_HEX}"  # Standard prefix + IP in hex
NUMERIC_ENGINE_ID="${ENGINE_ID:2}"  # Remove 0x prefix for matching

echo "===== SNMPv3 Trap Capture and Analysis ====="
echo "Expected Engine ID: $ENGINE_ID"

# 1. Make sure the container with our IP-based Engine ID is running
if ! docker ps | grep -q fluentd-snmp-trap-ip; then
  echo "Container fluentd-snmp-trap-ip is not running. Running setup script..."
  ./update-production-engine-id.sh
  sleep 5
fi

# Get container IP
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fluentd-snmp-trap-ip)
echo "Container IP address: $CONTAINER_IP"

# 2. Start packet capture on the host machine
echo "Starting packet capture. This will run in the background..."
OUTPUT_FILE="snmpv3_trap_capture.pcap"
sudo tcpdump -i any -w "$OUTPUT_FILE" -n "udp port 1162" &
TCPDUMP_PID=$!

# 3. Show tcpdump summary in a separate process
echo "Starting packet display (first 5 packets only)..."
sudo tcpdump -i any -n -v -c 5 "udp port 1162" &
DISPLAY_PID=$!

echo "Waiting 3 seconds for capture to start..."
sleep 3

# 4. Generate a test trap with the specific Engine ID
echo "Sending test trap with Engine ID: $ENGINE_ID"
TRAP_ID="WIRESHARK-TEST-$(date +%s)"

snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a SHA -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' \
  1.3.6.1.4.1.2011.2.15.1.7.1.0.1 \
  1.3.6.1.4.1.2011.2.15.1.7.1.1.1 s "TestNE-$TRAP_ID" 2>/dev/null

echo "Test trap sent. Waiting for processing..."
sleep 5

# 5. Check if the trap was received in container logs
echo "Checking if the trap was received by container..."
docker logs fluentd-snmp-trap-ip | grep -i "$TRAP_ID" || echo "Trap ID not found in logs"

# 6. Stop tcpdump
echo "Stopping packet capture..."
sudo kill $TCPDUMP_PID $DISPLAY_PID 2>/dev/null
sleep 1

# 7. Analyze capture file with tshark (command-line Wireshark)
echo "Analyzing captured packets..."
if command -v tshark &>/dev/null; then
  echo "Using tshark to analyze SNMP packets..."
  
  # Extract SNMPv3 msgAuthoritativeEngineID field
  echo "Extracting Engine ID from captured packets:"
  CAPTURED_IDS=$(tshark -r "$OUTPUT_FILE" -Y "snmp.msgAuthoritativeEngineID" -T fields -e snmp.msgAuthoritativeEngineID 2>/dev/null)
  
  if [ -n "$CAPTURED_IDS" ]; then
    echo "Found Engine IDs in capture:"
    echo "$CAPTURED_IDS"
    
    # Check if our expected Engine ID is in the capture
    if echo "$CAPTURED_IDS" | grep -qi "$NUMERIC_ENGINE_ID"; then
      echo -e "${GREEN}✅ SUCCESS: The expected Engine ID was found in the captured traffic!${NC}"
    else
      echo -e "${RED}❌ WARNING: The expected Engine ID was NOT found in the captured traffic.${NC}"
      echo "Expected: $NUMERIC_ENGINE_ID"
      echo "Found: $CAPTURED_IDS"
    fi
  else
    echo "No Engine IDs found in the capture."
  fi
  
  # Show the trap
  echo -e "\nSNMP trap details:"
  tshark -r "$OUTPUT_FILE" -Y "snmp.msgVersion == 3" -O snmp 2>/dev/null | head -50
else
  echo "tshark not found. Install with: sudo apt-get install tshark"
  echo "Capture saved to $OUTPUT_FILE. Open this file with Wireshark to analyze."
  echo "Look for the 'msgAuthoritativeEngineID' field in the SNMPv3 packets."
fi

echo -e "\n===== Capture Complete ====="
echo "Raw packet capture saved to: $OUTPUT_FILE"
echo "You can open this file in Wireshark for detailed analysis."
echo "In Wireshark, filter with: snmp.msgAuthoritativeEngineID"
echo "And verify that the Engine ID matches: $ENGINE_ID" 