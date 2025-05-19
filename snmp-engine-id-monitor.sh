#!/bin/bash
# Monitor SNMPv3 traps and extract Engine IDs
# This script requires net-snmp-utils to be installed

# Set up a temporary log file for snmptrapd
TEMP_LOG=$(mktemp)
ENGINE_ID_LOG=$(mktemp)
DEBUG_LOG=$(mktemp)
TRAP_PORT=1162

echo "=== SNMPv3 Engine ID Monitor (Enhanced) ==="
echo "Starting SNMPv3 trap listener on port $TRAP_PORT..."
echo "Press Ctrl+C to stop monitoring"
echo

# Check if port is already in use
if netstat -tuln | grep ":$TRAP_PORT " > /dev/null; then
    echo "⚠️ Warning: Port $TRAP_PORT is already in use!"
    echo "This may prevent the script from capturing traps."
    echo "Would you like to continue anyway? (y/n)"
    read -r response
    if [[ "$response" != "y" ]]; then
        echo "Exiting script."
        exit 1
    fi
fi

# Create a minimal snmptrapd configuration that logs all SNMPv3 details
cat > /tmp/snmptrapd-monitor.conf << EOF
authUser log,execute,net NCEadmin
createUser -e 0x8000000001020304 NCEadmin MD5 P@ssw0rdauth DES P@ssw0rddata
disableAuthorization yes
logOption f,e,s,S,D
format1 %B\n%v\n%W\n%V\n
outputOption ue
doNotLogTraps no
doNotRetainNotificationLogs no
EOF

# Start snmptrapd with comprehensive debugging
echo "Starting SNMPv3 trap daemon with enhanced debugging..."
snmptrapd -f -Lo -Dusm,receive,snmp,tdomain,transport,packet,all -C \
    -c /tmp/snmptrapd-monitor.conf -p /tmp/snmptrapd.pid \
    udp:localhost:$TRAP_PORT > "$TEMP_LOG" 2> "$DEBUG_LOG" &
SNMPTRAPD_PID=$!

# Wait a moment to ensure snmptrapd is started
sleep 2

# Check if snmptrapd is running
if ! ps -p $SNMPTRAPD_PID > /dev/null; then
    echo "❌ Error: Failed to start snmptrapd. See debug log for details."
    cat "$DEBUG_LOG"
    rm -f "$TEMP_LOG" "$ENGINE_ID_LOG" "$DEBUG_LOG" /tmp/snmptrapd-monitor.conf
    exit 1
fi

echo "Listening for SNMPv3 traps on port $TRAP_PORT..."
echo "Results will be displayed in real-time"
echo "Debug log: $DEBUG_LOG"
echo "--------------------------------------"

# Function to clean up on exit
cleanup() {
    echo -e "\nStopping SNMPv3 trap listener..."
    kill $SNMPTRAPD_PID 2>/dev/null
    rm -f "$TEMP_LOG" "$ENGINE_ID_LOG" "$DEBUG_LOG" /tmp/snmptrapd-monitor.conf /tmp/snmptrapd.pid
    exit 0
}

# Set up the trap for Ctrl+C
trap cleanup SIGINT SIGTERM

# Display initial debug information if available
if [ -s "$DEBUG_LOG" ]; then
    echo "Initial debug information:"
    head -n 10 "$DEBUG_LOG"
    echo "..."
fi

# Continuously monitor the log files for Engine ID information
while true; do
    # Check if any traps were received (even without engine ID)
    if grep -q "TRAP\|received" "$TEMP_LOG" 2>/dev/null; then
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] SNMP trap activity detected"
        tail -n 20 "$TEMP_LOG" | grep -i "trap\|received" | head -n 2
    fi
    
    # Extract Engine ID information from logs using multiple patterns
    (grep -i "engineid\|engine_id\|msgAuthoritativeEngineID" "$TEMP_LOG" 2>/dev/null || true;
     grep -i "engineid\|engine_id\|msgAuthoritativeEngineID" "$DEBUG_LOG" 2>/dev/null || true) | grep -v "^$" > "$ENGINE_ID_LOG"
    
    # If new engine IDs are found, display them
    if [ -s "$ENGINE_ID_LOG" ]; then
        while read -r line; do
            timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            
            # Extract engine ID using various formats
            if [[ $line =~ [eE]ngine[_]?[iI][dD][[:space:]]*[:=]?[[:space:]]*([0-9A-Fa-f]+) ]]; then
                engine_id="${BASH_REMATCH[1]}"
                echo -e "[$timestamp] 🔍 Received SNMPv3 trap with Engine ID: 0x$engine_id"
            elif [[ $line =~ [eE]ngine[_]?[iI][dD][[:space:]]*[:=]?[[:space:]]*0x([0-9A-Fa-f]+) ]]; then
                engine_id="${BASH_REMATCH[1]}"
                echo -e "[$timestamp] 🔍 Received SNMPv3 trap with Engine ID: 0x$engine_id"
            elif [[ $line =~ msgAuthoritativeEngineID[[:space:]]*[:=]?[[:space:]]*([0-9A-Fa-f]+) ]]; then
                engine_id="${BASH_REMATCH[1]}"
                echo -e "[$timestamp] 🔍 Received SNMPv3 trap with Engine ID (msgAuthoritativeEngineID): 0x$engine_id"
            else
                echo -e "[$timestamp] ℹ️ Engine ID related data detected:"
                echo "  $line"
            fi
        done < "$ENGINE_ID_LOG"
        
        # Clear the engine ID log for the next iteration
        > "$ENGINE_ID_LOG"
    fi
    
    # Check for hex dumps in the debug log that might contain engine IDs
    if grep -q "Hex dump" "$DEBUG_LOG" 2>/dev/null; then
        hex_dump=$(grep -A 10 "Hex dump" "$DEBUG_LOG" | head -n 11)
        if [ ! -z "$hex_dump" ]; then
            timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            echo -e "[$timestamp] 🔍 Possible SNMP packet detected, raw hex dump:"
            echo "$hex_dump"
            echo "..."
        fi
        # Remove processed hex dumps to avoid repeating
        sed -i '/Hex dump/,+10d' "$DEBUG_LOG"
    fi
    
    # Brief pause to reduce CPU usage
    sleep 1
done 