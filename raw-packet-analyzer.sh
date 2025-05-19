#!/bin/bash
# Raw UDP Packet Analyzer - For non-standard SNMP packet detection

# Configuration
INTERFACE="any"
PORT=1162
TEMP_FILE=$(mktemp)
OUTPUT_DIR="packet_dumps"
CAPTURE_COUNT=10
SHOW_ASCII=true

echo "=== Raw UDP Packet Analyzer ==="
echo "This script captures raw packets without assuming they follow standard formats"
echo "Press Ctrl+C to stop monitoring"
echo

# Check if we have tcpdump
if ! command -v tcpdump >/dev/null 2>&1; then
    echo "❌ Error: tcpdump is required but not installed."
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Function to clean up on exit
cleanup() {
    echo -e "\nStopping packet capture..."
    rm -f "$TEMP_FILE" 
    exit 0
}

# Set up the trap for Ctrl+C
trap cleanup SIGINT SIGTERM

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "⚠️ Warning: Not running as root. Packet capture might not work properly."
    echo "Please run with sudo: sudo $0"
fi

echo "Starting raw packet capture on interface $INTERFACE, port $PORT..."
echo "Saving packet dumps to $OUTPUT_DIR/"
echo "--------------------------------------"

# Function to display a hex dump in a readable format
display_hex_dump() {
    local file=$1
    
    # Extract binary data
    xxd -g 1 "$file" > "$file.xxd"
    
    # Display with line numbers and ASCII representation
    cat -n "$file.xxd"
}

# Function to search for common SNMP patterns
search_snmp_patterns() {
    local file=$1
    local hexdump
    
    # Convert to raw hex
    hexdump=$(xxd -p "$file" | tr -d '\n')
    
    echo "Searching for common SNMP patterns..."
    
    # Check for SNMPv3 header signature (30 = ASN.1 SEQUENCE)
    if echo "$hexdump" | grep -q "3082"; then
        echo "✓ Found ASN.1 SEQUENCE tag (possible SNMP packet)"
    fi
    
    # Look for common SNMP OIDs in hex
    if echo "$hexdump" | grep -q "2b06010"; then
        echo "✓ Found common SNMP OID pattern (starts with 1.3.6.1)"
    fi
    
    # Look for engine ID patterns - very flexible pattern matching
    # 80 is the typical first byte of an Engine ID
    if [[ $hexdump =~ (80[0-9a-f]{8,32}) ]]; then
        echo "✓ Possible Engine ID: 0x${BASH_REMATCH[1]}"
    fi
    
    # Try to extract string values that might help identify the packet
    strings "$file" | grep -i "trap\|snmp\|engine\|agent\|manager" > "$file.strings"
    if [ -s "$file.strings" ]; then
        echo "✓ Found SNMP-related strings:"
        cat "$file.strings"
    fi
}

# Main packet capture loop
packet_count=0
while true; do
    timestamp=$(date +"%Y%m%d_%H%M%S")
    output_file="$OUTPUT_DIR/packet_${timestamp}_${packet_count}.pcap"
    
    # Capture a single UDP packet on the specified port
    tcpdump -i "$INTERFACE" -c 1 -w "$output_file" -s 0 "udp port $PORT" 2>/dev/null
    
    # Check if we captured a packet
    if [ -s "$output_file" ]; then
        packet_count=$((packet_count+1))
        
        echo "========================================"
        echo "📦 Packet #$packet_count captured at $(date +"%Y-%m-%d %H:%M:%S")"
        
        # Get basic info about the packet
        tcpdump -r "$output_file" -n -v 2>/dev/null | head -n 10 > "$TEMP_FILE"
        
        # Display source and destination
        src=$(grep -oE "IP [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" "$TEMP_FILE" | head -1 | cut -d' ' -f2)
        dst=$(grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.$PORT" "$TEMP_FILE" | head -1 | sed "s/\.$PORT//")
        
        if [ -n "$src" ]; then
            echo "Source IP: $src"
        fi
        if [ -n "$dst" ]; then
            echo "Destination IP: $dst"
        fi
        
        # Extract the raw packet data to a text file
        tcpdump -r "$output_file" -xx 2>/dev/null > "$output_file.hex"
        
        # Display hex dump
        echo "Raw Packet Hex Dump:"
        display_hex_dump "$output_file.hex"
        
        # Try to analyze the content
        search_snmp_patterns "$output_file"
        
        echo "Full packet saved to: $output_file"
        echo "--------------------------------------"
        
        # Limit the number of saved files
        if [ $packet_count -gt $CAPTURE_COUNT ]; then
            oldest=$(ls -t "$OUTPUT_DIR"/packet_* 2>/dev/null | tail -1)
            if [ -n "$oldest" ]; then
                rm -f "$oldest" "$oldest.hex" "$oldest.hex.xxd" "$oldest.strings" 2>/dev/null
            fi
        fi
    else
        # Show a dot every 5 seconds to indicate we're still running
        if [ $((SECONDS % 5)) -eq 0 ]; then
            echo -n "."
        fi
    fi
    
    # Brief pause
    sleep 0.5
done 