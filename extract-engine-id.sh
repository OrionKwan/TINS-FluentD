#!/bin/bash
# Script to capture SNMPv3 traps and extract the Engine ID

# Parse command line arguments
ANALYZE_EXISTING=false
EXISTING_CAPTURE=""

while getopts "f:" opt; do
  case $opt in
    f)
      ANALYZE_EXISTING=true
      EXISTING_CAPTURE="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      echo "Usage: $0 [-f existing_capture.pcap]"
      exit 1
      ;;
  esac
done

# Configure capture settings
CAPTURE_FILE="engine_id_capture_$(date +%Y%m%d_%H%M%S).pcap"
CAPTURE_FILTER="udp port 1162"  # Standard SNMP trap port
INTERFACE="any"                 # Capture on all interfaces

echo "===== SNMPv3 Engine ID Extractor ====="
echo "This script will capture SNMPv3 traps and extract the source Engine ID prefix"
echo

if [ "$ANALYZE_EXISTING" = true ]; then
  echo "Analyzing existing capture file: $EXISTING_CAPTURE"
  if [ ! -f "$EXISTING_CAPTURE" ]; then
    echo "Error: Specified capture file does not exist: $EXISTING_CAPTURE"
    exit 1
  fi
  CAPTURE_FILE="$EXISTING_CAPTURE"
else
  echo "Capture file will be saved as: $CAPTURE_FILE"
  echo "Capture filter: $CAPTURE_FILTER"
  echo

  # Check if running as root (required for packet capture)
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
  fi

  # Check if tcpdump is available
  if ! command -v tcpdump &>/dev/null; then
    echo "tcpdump is not installed. Please install it with: sudo apt-get install tcpdump"
    exit 1
  fi

  # Check free disk space
  FREE_SPACE=$(df -m . | awk 'NR==2 {print $4}')
  if [ "$FREE_SPACE" -lt 100 ]; then
    echo "Warning: Low disk space ($FREE_SPACE MB). Capture may fail."
  fi

  # Create cleanup function for graceful exit
  cleanup() {
    echo "Cleaning up..."
    if [ -n "$TCPDUMP_PID" ] && kill -0 $TCPDUMP_PID 2>/dev/null; then
      kill $TCPDUMP_PID 2>/dev/null
    fi
    if [ -n "$DISPLAY_PID" ] && kill -0 $DISPLAY_PID 2>/dev/null; then
      kill $DISPLAY_PID 2>/dev/null
    fi
    exit 0
  }

  # Set trap for cleanup on various signals
  trap cleanup SIGINT SIGTERM EXIT

  # Start capture in background
  echo "Starting packet capture... (Press Enter after you've sent the trap)"
  tcpdump -i $INTERFACE -w "$CAPTURE_FILE" -n "$CAPTURE_FILTER" &
  TCPDUMP_PID=$!

  # Check if tcpdump started successfully
  sleep 1
  if ! kill -0 $TCPDUMP_PID 2>/dev/null; then
    echo "Error: Failed to start tcpdump capture. Check permissions."
    exit 1
  fi

  # Optionally show packets in real-time (in addition to saving them)
  tcpdump -i $INTERFACE -n "$CAPTURE_FILTER" &
  DISPLAY_PID=$!

  # Wait for user to indicate they've sent the trap
  echo
  echo "*** CAPTURE RUNNING ***"
  echo "1. Prepare your source device to send the SNMPv3 trap"
  echo "2. Send the trap when you're ready"
  echo "3. Wait a few seconds after sending to ensure capture"
  echo "4. Press Enter to stop capturing"
  read -r

  # Stop capture properly
  echo
  echo "Stopping packet capture..."
  if [ -n "$TCPDUMP_PID" ] && kill -0 $TCPDUMP_PID 2>/dev/null; then
    kill $TCPDUMP_PID 2>/dev/null
    # Wait for tcpdump to properly close the file
    wait $TCPDUMP_PID 2>/dev/null
  fi
  if [ -n "$DISPLAY_PID" ] && kill -0 $DISPLAY_PID 2>/dev/null; then
    kill $DISPLAY_PID 2>/dev/null
    wait $DISPLAY_PID 2>/dev/null
  fi
  sleep 2

  # Check if the capture file exists and has content
  if [ ! -f "$CAPTURE_FILE" ]; then
    echo "Error: Capture file not created. Check permissions."
    exit 1
  fi

  if [ ! -s "$CAPTURE_FILE" ]; then
    echo "Warning: Capture file is empty."
    exit 1
  fi
fi

# Analysis section starts here - common for new captures and existing files
echo
echo "Analyzing capture file: $CAPTURE_FILE"

# Check if we captured anything
PACKET_COUNT=$(tcpdump -r "$CAPTURE_FILE" -n 2>/dev/null | wc -l)
echo "Captured $PACKET_COUNT packets"

if [ "$PACKET_COUNT" -gt 0 ]; then
  echo
  echo "Capture successful! Analyzing SNMPv3 Engine IDs..."
  
  # First analyze general UDP traffic to port 1162
  echo
  echo "===== UDP Traffic Analysis ====="
  echo "Packets to port 1162:"
  tcpdump -r "$CAPTURE_FILE" -n "udp port 1162" | head -10
  
  # Use tshark to extract the Engine IDs if available
  if command -v tshark &>/dev/null; then
    echo
    echo "===== Engine ID Analysis ====="
    
    # Extract SNMPv3 packets and their Engine IDs
    SNMPV3_COUNT=$(tshark -r "$CAPTURE_FILE" -Y "snmp.msgVersion == 3" 2>/dev/null | wc -l)
    echo "SNMPv3 packets found: $SNMPV3_COUNT"
    
    if [ "$SNMPV3_COUNT" -gt 0 ]; then
      echo
      echo "Extracting Engine IDs from SNMPv3 packets..."
      
      # Display source IP and Engine ID for each SNMPv3 packet
      echo "Source IP -> Engine ID mapping:"
      echo "-------------------------------"
      tshark -r "$CAPTURE_FILE" -Y "snmp.msgVersion == 3" -T fields \
        -e ip.src -e snmp.msgAuthoritativeEngineID -E header=y -E separator=" -> " | sort | uniq
      
      echo
      echo "Detailed Engine ID analysis:"
      echo "----------------------------"
      for ENGINE_ID in $(tshark -r "$CAPTURE_FILE" -Y "snmp.msgVersion == 3" -T fields -e snmp.msgAuthoritativeEngineID | sort | uniq); do
        echo "Engine ID: $ENGINE_ID"
        
        # Try to determine if this is an IP-based Engine ID
        if [[ ${#ENGINE_ID} -ge 24 && "$ENGINE_ID" == *"80:00:00:00:c0:01"* ]]; then
          # Extract potential IP portion (last 8 hex digits from a standard IP-based Engine ID)
          IP_HEX="${ENGINE_ID:18:8}"
          IP_BYTES=(${IP_HEX//:/ })
          
          # Check if we have 4 bytes for an IP address
          if [ ${#IP_BYTES[@]} -eq 4 ]; then
            POTENTIAL_IP=""
            for byte in "${IP_BYTES[@]}"; do
              POTENTIAL_IP+="$((16#$byte))."
            done
            POTENTIAL_IP=${POTENTIAL_IP%?}  # Remove trailing dot
            
            echo "  ↳ This appears to be an IP-based Engine ID"
            echo "  ↳ Hex format: $ENGINE_ID"
            echo "  ↳ Prefix: 80:00:00:00:c0:01"
            echo "  ↳ IP portion (hex): $IP_HEX"
            echo "  ↳ Decoded IP: $POTENTIAL_IP"
          else
            echo "  ↳ This may be an IP-based Engine ID but couldn't decode the IP"
          fi
        else
          echo "  ↳ This does not appear to be an IP-based Engine ID"
          echo "  ↳ Full hex value: $ENGINE_ID"
        fi
      done
    else
      echo "No SNMPv3 packets found in the capture. Checking for other SNMP versions..."
      # Also check for general SNMP packets
      SNMP_COUNT=$(tshark -r "$CAPTURE_FILE" -Y "snmp" 2>/dev/null | wc -l)
      if [ "$SNMP_COUNT" -gt 0 ]; then
        echo "Found $SNMP_COUNT SNMP packets, but they're not SNMPv3."
        echo "SNMP versions detected:"
        tshark -r "$CAPTURE_FILE" -Y "snmp" -T fields -e snmp.msgVersion 2>/dev/null | sort | uniq -c
        
        echo
        echo "Extracting SNMP information:"
        echo "----------------------------"
        tshark -r "$CAPTURE_FILE" -Y "snmp" -T fields -e ip.src -e snmp.msgVersion -e snmp.community 2>/dev/null | sort | uniq
      else
        echo "No SNMP packets detected of any version."
        
        # Check for any UDP packets to target port
        echo
        echo "Checking general UDP packets to port 1162 (not recognized as SNMP by tshark):"
        UDP_COUNT=$(tshark -r "$CAPTURE_FILE" -Y "udp.dstport == 1162" 2>/dev/null | wc -l)
        echo "UDP packets to port 1162: $UDP_COUNT"
        
        if [ "$UDP_COUNT" -gt 0 ]; then
          echo "Packets may be malformed or using a non-standard SNMP format."
          echo
          echo "First few bytes of each packet (raw hex):"
          tshark -r "$CAPTURE_FILE" -Y "udp.dstport == 1162" -T fields -e data | head -5
        fi
      fi
    fi
  else
    echo "tshark not found. Install with: sudo apt-get install tshark"
    echo "Capture saved to $CAPTURE_FILE. Open this file with Wireshark to analyze."
    
    # Provide basic info using tcpdump
    echo
    echo "Basic packet info using tcpdump:"
    tcpdump -r "$CAPTURE_FILE" -n -v | head -20
  fi
else
  echo "No packets captured. Try again with a larger time window."
  # Check if we can see packets in real-time even though capture failed
  if [ "$ANALYZE_EXISTING" = false ]; then
    echo
    echo "Running a brief live capture to verify packets are arriving:"
    timeout 5 tcpdump -i $INTERFACE -n "$CAPTURE_FILTER" -v
  fi
fi 