#!/bin/bash

# Script to capture SNMP trap traffic on port 1162
# Step 1: SNMP Trap Capturing for OnBoarding process
# Usage: ./capture_snmp_traps.sh [duration_in_seconds] [output_filename]

# Default values
DURATION=${1:-60}  # Default capture duration: 60 seconds
CAPTURE_DIR="$(dirname "$0")/1. Test Trap Capturing"  # Use the designated capture directory
OUTPUT_FILE=${2:-"$CAPTURE_DIR/snmp_traps_$(date +%Y%m%d_%H%M%S).pcap"}  # Default filename with timestamp
INTERFACE="ens160"  # Interface to capture on
PORT=1162  # SNMP trap port

echo "======== SNMP TRAP CAPTURE TOOL - ONBOARDING STEP 1 ========"
echo "Starting packet capture on interface $INTERFACE for port $PORT"
echo "Capture will run for $DURATION seconds"
echo "Output will be saved to: $OUTPUT_FILE"
echo "=========================================================="

# Create output directory if it doesn't exist
mkdir -p "$CAPTURE_DIR"

# Run tcpdump with the specified parameters
# -i: interface
# -w: write to file
# -G: rotate after specified seconds
# -W: limit to one output file
# udp port 1162: capture only UDP packets on port 1162
sudo tcpdump -i $INTERFACE udp port $PORT -w "$OUTPUT_FILE" -G $DURATION -W 1

# Check if capture was successful
if [ -f "$OUTPUT_FILE" ]; then
    echo "=========================================================="
    echo "Capture complete! Saved to $OUTPUT_FILE"
    echo "File information:"
    ls -lh "$OUTPUT_FILE"
    echo "To analyze this file, use: wireshark \"$OUTPUT_FILE\""
    echo "=========================================================="
else
    echo "Error: Capture failed. Output file was not created."
    echo "Make sure you have permission to run tcpdump and write to the output directory."
fi 