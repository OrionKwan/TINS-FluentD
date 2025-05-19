#!/bin/bash
# Script to capture SNMPv3 traps specifically from source IP 172.29.36.80

# Set the source IP we want to filter
SOURCE_IP="172.29.36.80"
IP_HEX=$(printf '%02X%02X%02X%02X' $(echo $SOURCE_IP | tr '.' ' '))
ENGINE_ID="0x80000000c001${IP_HEX}"  # Standard prefix + IP in hex

echo "===== Capturing SNMPv3 Traps from Source IP: $SOURCE_IP ====="
echo "Expected Engine ID: $ENGINE_ID"

# 1. Make sure our trap receiver container is running
if ! docker ps | grep -q fluentd-snmp-trap-ip; then
  echo "Container fluentd-snmp-trap-ip is not running. Running setup script..."
  ./update-production-engine-id.sh
  sleep 5
fi

# Get container IP
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fluentd-snmp-trap-ip)
CONTAINER_PORT=1162
echo "Container IP address: $CONTAINER_IP:$CONTAINER_PORT"

# 2. Start packet capture with source IP filter
echo "Starting packet capture for traffic from $SOURCE_IP. This will run in the background..."
OUTPUT_FILE="source_ip_${SOURCE_IP}_trap_capture.pcap"

# Capture packets that match source IP and port 1162
sudo tcpdump -i any -w "$OUTPUT_FILE" -n "host $SOURCE_IP and udp port 1162" &
TCPDUMP_PID=$!

# Also show the capture in real-time
echo "Starting packet display..."
sudo tcpdump -i any -n -v "host $SOURCE_IP and udp port 1162" &
DISPLAY_PID=$!

echo "Waiting 3 seconds for capture to start..."
sleep 3

# 3. Simulate a trap from the source IP (optional)
echo "Would you like to simulate a trap from $SOURCE_IP? (y/n)"
read -r SIMULATE

if [[ "$SIMULATE" == "y" || "$SIMULATE" == "Y" ]]; then
  echo "Simulating trap from $SOURCE_IP with Engine ID: $ENGINE_ID"
  TRAP_ID="SOURCE-IP-TEST-$(date +%s)"
  
  # We'll use the -S option to spoof the source IP
  # Note: This requires sudo privileges and might not work on all systems
  sudo snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a SHA -A P@ssw0rdauth \
    -x AES -X P@ssw0rddata -l authPriv -S $SOURCE_IP $CONTAINER_IP:$CONTAINER_PORT '' \
    1.3.6.1.4.1.2011.2.15.1.7.1.0.1 \
    1.3.6.1.4.1.2011.2.15.1.7.1.1.1 s "TestNE-$TRAP_ID" 2>/dev/null
    
  echo "Simulated trap sent. Waiting for processing..."
  sleep 5
  
  # Check container logs
  echo "Checking if trap was received by container..."
  docker logs fluentd-snmp-trap-ip | grep -i "$TRAP_ID" || echo "Trap ID not found in logs"
else
  echo "Waiting for real trap from $SOURCE_IP..."
  echo "Press Enter to stop capturing..."
  read -r
fi

# 4. Stop capture
echo "Stopping packet capture..."
sudo kill $TCPDUMP_PID $DISPLAY_PID 2>/dev/null
sleep 1

# 5. Analyze with tshark
echo "Analyzing captured packets..."
if command -v tshark &>/dev/null; then
  echo "Using tshark to analyze captured packets..."
  
  # Count SNMP packets from our source IP
  PACKET_COUNT=$(tshark -r "$OUTPUT_FILE" -Y "ip.src == $SOURCE_IP and snmp" -T fields -e frame.number | wc -l)
  echo "Found $PACKET_COUNT SNMP packets from source IP $SOURCE_IP"
  
  if [ "$PACKET_COUNT" -gt 0 ]; then
    # Show packet details
    echo -e "\nPacket summary:"
    tshark -r "$OUTPUT_FILE" -Y "ip.src == $SOURCE_IP and snmp" -T fields -e frame.number -e frame.time -e ip.src -e snmp.msgVersion
    
    # Check for SNMPv3 packets specifically
    SNMPV3_COUNT=$(tshark -r "$OUTPUT_FILE" -Y "ip.src == $SOURCE_IP and snmp.msgVersion == 3" -T fields -e frame.number | wc -l)
    echo "Found $SNMPV3_COUNT SNMPv3 packets from source IP $SOURCE_IP"
    
    if [ "$SNMPV3_COUNT" -gt 0 ]; then
      # Extract Engine IDs
      echo -e "\nEngine IDs found in SNMPv3 packets:"
      tshark -r "$OUTPUT_FILE" -Y "ip.src == $SOURCE_IP and snmp.msgVersion == 3" -T fields -e snmp.msgAuthoritativeEngineID
      
      # Detailed SNMP analysis
      echo -e "\nDetailed SNMP packet content (first packet only):"
      tshark -r "$OUTPUT_FILE" -Y "ip.src == $SOURCE_IP and snmp.msgVersion == 3" -O snmp | head -30
    fi
  fi
else
  echo "tshark not found. Install with: sudo apt-get install tshark"
  echo "Capture saved to $OUTPUT_FILE. Open this file with Wireshark to analyze."
fi

echo -e "\n===== Wireshark Filter Commands ====="
echo "To view these packets in Wireshark GUI, open $OUTPUT_FILE and use these filters:"
echo "1. Filter by source IP:           ip.src == $SOURCE_IP"
echo "2. Filter by source IP and SNMP:  ip.src == $SOURCE_IP && snmp"
echo "3. Filter by SNMPv3 only:         ip.src == $SOURCE_IP && snmp.msgVersion == 3"
echo "4. Filter by Engine ID:           snmp.msgAuthoritativeEngineID == $ENGINE_ID"
echo
echo "Capture file location: $(pwd)/$OUTPUT_FILE" 