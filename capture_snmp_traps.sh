#!/bin/bash

# Script to capture SNMP trap traffic on port 1162
# Usage: ./capture_snmp_traps.sh [duration_in_seconds] [output_filename]

# Default values
DURATION=${1:-60}  # Default capture duration: 60 seconds
OUTPUT_FILE=${2:-"snmp_traps_$(date +%Y%m%d_%H%M%S).pcap"}  # Default filename with timestamp
INTERFACE="ens160"  # Interface to capture on
PORT=1162  # SNMP trap port

echo "Starting packet capture on interface $INTERFACE for port $PORT"
echo "Capture will run for $DURATION seconds"
echo "Output will be saved to: $OUTPUT_FILE"

# Run tcpdump with the specified parameters
# -i: interface
# -c: packet count (not used here, using time-based capture)
# -w: write to file
# udp port 1162: capture only UDP packets on port 1162
sudo tcpdump -i $INTERFACE udp port $PORT -w "$OUTPUT_FILE" -G $DURATION -W 1

echo "Capture complete! Saved to $OUTPUT_FILE"
echo "File information:"
ls -lh "$OUTPUT_FILE" 