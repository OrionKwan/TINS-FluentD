#!/bin/bash
# Monitor existing snmptrapd for SNMPv3 trap engine IDs

# Configuration
SNMPTRAPD_LOG="/var/log/snmptrapd.log"
TEMP_LOG=$(mktemp)
ENGINE_ID_LOG=$(mktemp)
POLL_INTERVAL=1

echo "=== SNMPv3 Engine ID Monitor (External) ==="
echo "Monitoring existing snmptrapd process"
echo "Press Ctrl+C to stop monitoring"
echo

# Check if snmptrapd is actually running
if ! pgrep snmptrapd > /dev/null; then
    echo "❌ Error: No snmptrapd process found running!"
    echo "Please ensure snmptrapd is running before using this monitor."
    exit 1
fi

# Get the port where snmptrapd is listening
SNMP_PORT=$(netstat -tulpn 2>/dev/null | grep snmptrapd | grep udp | awk '{print $4}' | cut -d: -f2)
if [ -z "$SNMP_PORT" ]; then
    SNMP_PORT="unknown"
fi

echo "Found snmptrapd listening on UDP port: $SNMP_PORT"

# Check if the log file exists and is readable
if [ ! -r "$SNMPTRAPD_LOG" ]; then
    echo "⚠️ Warning: Cannot read the standard log file at $SNMPTRAPD_LOG."
    echo "Checking for alternative log locations..."
    
    # Try to find alternative log locations
    ALT_LOGS=$(find /var/log -name "*trap*" -o -name "*snmp*" 2>/dev/null | grep -v "\.gz$")
    if [ -n "$ALT_LOGS" ]; then
        echo "Found potential alternative log files:"
        echo "$ALT_LOGS"
        echo "Please specify which log file to monitor:"
        read -r SNMPTRAPD_LOG
        
        if [ ! -r "$SNMPTRAPD_LOG" ]; then
            echo "❌ Error: Cannot read the specified log file."
            exit 1
        fi
    else
        echo "❌ Error: Cannot find any snmptrapd log files."
        echo "You might need to run this script with sudo to access log files."
        exit 1
    fi
fi

echo "Monitoring log file: $SNMPTRAPD_LOG"
echo "--------------------------------------"

# Function to clean up on exit
cleanup() {
    echo -e "\nStopping SNMPv3 monitor..."
    rm -f "$TEMP_LOG" "$ENGINE_ID_LOG"
    exit 0
}

# Set up the trap for Ctrl+C
trap cleanup SIGINT SIGTERM

# Get initial position in the log file
INITIAL_SIZE=$(wc -c < "$SNMPTRAPD_LOG")

# Continuously monitor the log file for Engine ID information
while true; do
    # Check if the log file size has increased
    CURRENT_SIZE=$(wc -c < "$SNMPTRAPD_LOG")
    
    if [ "$CURRENT_SIZE" -gt "$INITIAL_SIZE" ]; then
        # Extract the new lines from the log file
        tail -c $(($CURRENT_SIZE - $INITIAL_SIZE)) "$SNMPTRAPD_LOG" > "$TEMP_LOG"
        INITIAL_SIZE=$CURRENT_SIZE
        
        # Check if any traps were received
        if grep -q "TRAP\|trap\|Trap\|received" "$TEMP_LOG" 2>/dev/null; then
            timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            echo "[$timestamp] 📬 SNMP trap activity detected"
            grep -i "trap\|received" "$TEMP_LOG" | head -n 2
        fi
        
        # Extract any engine ID information from the logs using multiple patterns
        grep -i "engine\|ID\|snmpv3\|authoritativeEngineID" "$TEMP_LOG" | grep -v "^$" > "$ENGINE_ID_LOG"
        
        # If engine IDs are found, display them
        if [ -s "$ENGINE_ID_LOG" ]; then
            while read -r line; do
                timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                
                # Extract engine ID using various formats
                if [[ $line =~ [eE]ngine[_]?[iI][dD][[:space:]]*[:=]?[[:space:]]*([0-9A-Fa-f]+) ]]; then
                    engine_id="${BASH_REMATCH[1]}"
                    echo -e "[$timestamp] 🔍 Detected Engine ID: 0x$engine_id"
                elif [[ $line =~ [eE]ngine[_]?[iI][dD][[:space:]]*[:=]?[[:space:]]*0x([0-9A-Fa-f]+) ]]; then
                    engine_id="${BASH_REMATCH[1]}"
                    echo -e "[$timestamp] 🔍 Detected Engine ID: 0x$engine_id"
                # Try to extract any hex string that could be an engine ID
                elif [[ $line =~ ([0-9A-Fa-f]{10,50}) ]]; then
                    hex_string="${BASH_REMATCH[1]}"
                    echo -e "[$timestamp] 🔍 Possible Engine ID (hex): 0x$hex_string"
                    echo "  Context: $line"
                else
                    echo -e "[$timestamp] ℹ️ Engine ID related information:"
                    echo "  $line"
                fi
            done < "$ENGINE_ID_LOG"
            
            # Clear the engine ID log for the next iteration
            > "$ENGINE_ID_LOG"
        fi
        
        # Look for hex dumps in raw format that might contain engine IDs
        if grep -q "0x" "$TEMP_LOG" 2>/dev/null; then
            while read -r line; do
                if [[ $line =~ 0x([0-9A-Fa-f]{10,50}) ]]; then
                    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                    hex_string="${BASH_REMATCH[1]}"
                    echo -e "[$timestamp] 🔍 Raw hex data possibly containing Engine ID: 0x$hex_string"
                fi
            done < <(grep "0x" "$TEMP_LOG")
        fi
    fi
    
    # Use tcpdump to directly capture packets on port 1162
    if command -v tcpdump >/dev/null 2>&1; then
        # Run a quick tcpdump capture to catch any fresh packets
        timeout 1 tcpdump -c 1 -i any -s0 -xX port $SNMP_PORT 2>/dev/null > "$TEMP_LOG"
        if grep -q "SNMPv3" "$TEMP_LOG"; then
            timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            echo -e "[$timestamp] 📡 Live SNMPv3 packet detected on port $SNMP_PORT"
            # Try to extract msgAuthoritativeEngineID
            if grep -A 10 -B 2 "msgAuthoritativeEngineID" "$TEMP_LOG" > "$ENGINE_ID_LOG"; then
                cat "$ENGINE_ID_LOG"
            fi
        fi
    fi
    
    # Brief pause to reduce CPU usage
    sleep $POLL_INTERVAL
done 