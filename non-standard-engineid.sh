#!/bin/bash
# Non-Standard SNMPv3 Engine ID Detection Script

# Configuration
IP_ADDRESS="172.29.36.80"
INTERFACE="any"
TRAP_PORT=1162
TEMP_FILE=$(mktemp)
HEX_FILE=$(mktemp)

echo "=== Non-Standard SNMPv3 Engine ID Detector ==="
echo "Target IP: $IP_ADDRESS"
echo "Listening on interface: $INTERFACE, port: $TRAP_PORT"
echo "Press Ctrl+C to stop monitoring"
echo

# Check if we have tcpdump
if ! command -v tcpdump >/dev/null 2>&1; then
    echo "❌ Error: tcpdump is required but not installed."
    exit 1
fi

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "⚠️ Warning: Not running as root. Packet capture requires root privileges."
    echo "Please run with sudo: sudo $0"
    echo "Continuing anyway, but expect no results..."
fi

# Function to clean up on exit
cleanup() {
    echo -e "\nStopping packet capture..."
    rm -f "$TEMP_FILE" "$HEX_FILE"
    exit 0
}

# Set up the trap for Ctrl+C
trap cleanup SIGINT SIGTERM

# Convert IP to hex
ip_to_hex() {
    local ip=$1
    local hex=""
    for octet in $(echo $ip | tr '.' ' '); do
        hex=$(printf "%s%02X" "$hex" "$octet")
    done
    echo "$hex"
}

IP_HEX=$(ip_to_hex "$IP_ADDRESS")
echo "IP in hex: $IP_HEX"
echo

echo "Starting packet capture..."
echo "--------------------------------------"

# Function to extract potential engine IDs using various patterns
extract_potential_engine_ids() {
    local hexdata=$1
    local matches=()
    local found=false

    # Common SNMP patterns to look for (very flexible)
    patterns=(
        # Standard patterns
        "80[0-9a-f]{8,32}"         # Starts with 0x80 (standard)
        "80[0-9a-f]*$IP_HEX"       # Contains the IP in hex
        "04[0-9a-f]{2}80[0-9a-f]+" # ASN.1 OCTET STRING followed by engine ID
        
        # Non-standard but possible patterns
        "30[0-9a-f]{2}02[0-9a-f]{2}03"  # SNMPv3 header pattern
        "[0-9a-f]{16,40}"              # Any substantial hex sequence
    )
    
    # Try all patterns
    for pattern in "${patterns[@]}"; do
        if [[ $hexdata =~ ($pattern) ]]; then
            matches+=("${BASH_REMATCH[1]}")
            found=true
        fi
    done
    
    # Output matches
    if $found; then
        for match in "${matches[@]}"; do
            echo "  - 0x$match"
        done
        return 0
    else
        return 1
    fi
}

# Main loop to capture and analyze packets
packet_count=0
while true; do
    # Capture packets with focus on the target IP
    tcpdump -i "$INTERFACE" -s0 -c 1 -w "$TEMP_FILE" \
        "udp port $TRAP_PORT and (host $IP_ADDRESS or dst port $TRAP_PORT)" 2>/dev/null
    
    if [ -s "$TEMP_FILE" ]; then
        packet_count=$((packet_count+1))
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] 📦 UDP packet #$packet_count captured"
        
        # Extract packet content in hexadecimal
        hexdump -C "$TEMP_FILE" > "$HEX_FILE"
        
        # Get source and destination
        packet_info=$(tcpdump -r "$TEMP_FILE" -nn -v 2>/dev/null | head -n 1)
        echo "Packet info: $packet_info"
        
        # Convert to a single hex string for pattern matching
        hex_content=$(xxd -p "$TEMP_FILE" | tr -d '\n')
        
        # Look for ASN.1 structure markers (type+length patterns)
        if echo "$hex_content" | grep -q "3082"; then
            echo "✓ ASN.1 sequence detected (typical of SNMP packets)"
        fi
        
        # Try to find potential engine IDs
        echo "Checking for potential engine IDs..."
        if extract_potential_engine_ids "$hex_content"; then
            echo "✓ Potential engine IDs found (shown above)"
        else
            echo "⚠️ No standard engine ID patterns detected"
            
            # Show some of the packet content for manual inspection
            echo "Packet hex dump (first 16 lines):"
            head -n 16 "$HEX_FILE"
            echo "..."
        fi
        
        # Check for plain text indicators
        if strings "$TEMP_FILE" | grep -i -q "snmp\|trap\|engin"; then
            echo "✓ SNMP-related text found in packet:"
            strings "$TEMP_FILE" | grep -i "snmp\|trap\|engin" | sed 's/^/  /'
        fi
        
        echo "--------------------------------------"
    else
        # Show a dot every 10 seconds to indicate we're still running
        if [ $((SECONDS % 10)) -eq 0 ]; then
            echo -n "."
        fi
    fi
    
    # Brief pause to avoid overwhelming the system
    sleep 0.5
done 