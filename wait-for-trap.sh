#!/bin/bash
# Script to capture SNMP traffic, waiting for the user to signal they've sent the trap

# Configure capture settings
CAPTURE_FILE="wait_for_trap_$(date +%Y%m%d_%H%M%S).pcap"
CAPTURE_FILTER="udp port 1162"  # Standard SNMP trap port
INTERFACE="any"                 # Capture on all interfaces

echo "===== SNMP Trap Capture (Wait Mode) ====="
echo "This script will start capturing SNMP trap traffic"
echo "and wait until you signal that you've sent the trap from your source device."
echo
echo "Capture file will be saved as: $CAPTURE_FILE"
echo "Capture filter: $CAPTURE_FILTER"
echo

# Check if running as root (required for packet capture)
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

# Start capture in background
echo "Starting packet capture... (Press Enter after you've sent the trap)"
tcpdump -i $INTERFACE -w "$CAPTURE_FILE" -n "$CAPTURE_FILTER" -v &
TCPDUMP_PID=$!

# Optionally show packets in real-time (in addition to saving them)
tcpdump -i $INTERFACE -n "$CAPTURE_FILTER" -v &
DISPLAY_PID=$!

# Wait for user to indicate they've sent the trap
echo
echo "*** CAPTURE RUNNING ***"
echo "1. Prepare your source device to send the SNMPv3 trap"
echo "2. Send the trap when you're ready"
echo "3. Wait a few seconds after sending to ensure capture"
echo "4. Press Enter to stop capturing"
read -r

# Stop capture
echo
echo "Stopping packet capture..."
kill $TCPDUMP_PID $DISPLAY_PID 2>/dev/null
sleep 1

# Check if we captured anything
PACKET_COUNT=$(tcpdump -r "$CAPTURE_FILE" -n | wc -l)
echo "Captured $PACKET_COUNT packets"

if [ "$PACKET_COUNT" -gt 0 ]; then
  echo
  echo "Capture successful! File saved as: $CAPTURE_FILE"
  echo
  echo "To view in Wireshark:"
  echo "1. Configure Wireshark with your SNMPv3 credentials:"
  echo "   - Edit → Preferences → Protocols → SNMP"
  echo "   - Add your SNMPv3 user (NCEadmin) with SHA/AES auth"
  echo "2. Open the capture file in Wireshark"
  echo "3. Use display filter: snmp.msgVersion == 3"
  echo
  echo "You can now open this file in Wireshark with:"
  echo "wireshark \"$CAPTURE_FILE\""
else
  echo "No packets captured. Try again with a larger time window."
fi 