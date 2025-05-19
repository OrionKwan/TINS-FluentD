#!/bin/bash

# SNMPv3 Engine ID Test Script
# This script helps discover and test SNMPv3 Engine IDs

# Default values
HOST=""
PORT="161"
USERNAME="snmpuser"
AUTH_PASS="authpassword"
PRIV_PASS="privpassword"
AUTH_PROTOCOL="SHA"
PRIV_PROTOCOL="AES"
MODE="discover"
ENGINE_ID=""

# Function to show usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --host HOST         Target hostname or IP (required)"
    echo "  -p, --port PORT         SNMP port (default: 161)"
    echo "  -u, --user USERNAME     SNMPv3 username (default: snmpuser)"
    echo "  -a, --auth PASSWORD     Authentication password (default: authpassword)"
    echo "  -x, --priv PASSWORD     Privacy password (default: privpassword)"
    echo "  -A, --auth-protocol PROTO Authentication protocol: MD5|SHA (default: SHA)"
    echo "  -X, --priv-protocol PROTO Privacy protocol: DES|AES (default: AES)"
    echo "  -m, --mode MODE         Operation mode: discover|test|trap (default: discover)"
    echo "  -e, --engine-id ID      Engine ID (required for test and trap modes)"
    echo "  --help                  Display this help and exit"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host)
            HOST="$2"
            shift 2
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -u|--user)
            USERNAME="$2"
            shift 2
            ;;
        -a|--auth)
            AUTH_PASS="$2"
            shift 2
            ;;
        -x|--priv)
            PRIV_PASS="$2"
            shift 2
            ;;
        -A|--auth-protocol)
            AUTH_PROTOCOL="$2"
            shift 2
            ;;
        -X|--priv-protocol)
            PRIV_PROTOCOL="$2"
            shift 2
            ;;
        -m|--mode)
            MODE="$2"
            shift 2
            ;;
        -e|--engine-id)
            ENGINE_ID="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check for required arguments
if [ -z "$HOST" ]; then
    echo "Error: Host (-h, --host) is required."
    usage
fi

if [[ "$MODE" != "discover" && -z "$ENGINE_ID" ]]; then
    echo "Error: Engine ID (-e, --engine-id) is required for test and trap modes."
    usage
fi

# Function to discover Engine ID
discover_engine_id() {
    echo "Attempting to discover Engine ID for $HOST..."
    
    # Method 1: Using snmpwalk with noAuthNoPriv
    echo "Method 1: Using snmpwalk with noAuthNoPriv..."
    RESULT=$(snmpwalk -v 3 -l noAuthNoPriv -u "$USERNAME" "$HOST" 2>&1)
    
    # Check if we got an Engine ID from the error message
    if echo "$RESULT" | grep -q "Engine ID"; then
        ENGINE_ID=$(echo "$RESULT" | grep "Engine ID" | sed -e 's/.*Engine ID: //')
        echo "Discovered Engine ID: $ENGINE_ID"
    else
        echo "Could not discover Engine ID using Method 1."
        echo "Output: $RESULT"
        
        # Method 2: Check if snmpd.conf exists locally
        echo "Method 2: Checking local snmpd.conf..."
        if [ -f "/etc/snmp/snmpd.conf" ]; then
            LOCAL_ENGINE_ID=$(grep -i engineID /etc/snmp/snmpd.conf | grep -v "^#" | awk '{print $2}')
            if [ -n "$LOCAL_ENGINE_ID" ]; then
                echo "Found local Engine ID in /etc/snmp/snmpd.conf: $LOCAL_ENGINE_ID"
                echo "Note: This may not be the remote device's Engine ID."
            else
                echo "No Engine ID found in local snmpd.conf."
            fi
        else
            echo "Local snmpd.conf not found or not accessible."
        fi
        
        echo "Try specifying the Engine ID manually with -e option after discovering it."
    fi
}

# Function to test SNMPv3 with Engine ID
test_snmpv3() {
    echo "Testing SNMPv3 with Engine ID: $ENGINE_ID"
    echo "Host: $HOST, Username: $USERNAME"
    echo "Auth: $AUTH_PROTOCOL, Priv: $PRIV_PROTOCOL"
    
    # Try with various Engine ID formats
    ENGINE_ID_PLAIN=$(echo "$ENGINE_ID" | tr -d ':' | tr -d '0x')
    ENGINE_ID_COLON=$(echo "$ENGINE_ID_PLAIN" | sed 's/\(..\)/\1:/g' | sed 's/:$//')
    ENGINE_ID_0X="0x$ENGINE_ID_PLAIN"
    
    echo "Testing with plain format: $ENGINE_ID_PLAIN"
    snmpget -v 3 -E "$ENGINE_ID_PLAIN" -l authPriv -u "$USERNAME" -a "$AUTH_PROTOCOL" -A "$AUTH_PASS" -x "$PRIV_PROTOCOL" -X "$PRIV_PASS" "$HOST:$PORT" SNMPv2-MIB::sysDescr.0
    
    echo "Testing with colon format: $ENGINE_ID_COLON"
    snmpget -v 3 -E "$ENGINE_ID_COLON" -l authPriv -u "$USERNAME" -a "$AUTH_PROTOCOL" -A "$AUTH_PASS" -x "$PRIV_PROTOCOL" -X "$PRIV_PASS" "$HOST:$PORT" SNMPv2-MIB::sysDescr.0
    
    echo "Testing with 0x prefix: $ENGINE_ID_0X"
    snmpget -v 3 -E "$ENGINE_ID_0X" -l authPriv -u "$USERNAME" -a "$AUTH_PROTOCOL" -A "$AUTH_PASS" -x "$PRIV_PROTOCOL" -X "$PRIV_PASS" "$HOST:$PORT" SNMPv2-MIB::sysDescr.0
}

# Function to send test trap
send_trap() {
    echo "Sending test trap to $HOST:$PORT with Engine ID: $ENGINE_ID"
    snmptrap -v 3 -e "$ENGINE_ID" -l authPriv -u "$USERNAME" -a "$AUTH_PROTOCOL" -A "$AUTH_PASS" -x "$PRIV_PROTOCOL" -X "$PRIV_PASS" "$HOST:$PORT" '' SNMPv2-MIB::coldStart.0
    echo "Trap sent. Check the receiver logs to confirm receipt."
}

# Execute the appropriate function based on mode
case "$MODE" in
    discover)
        discover_engine_id
        ;;
    test)
        test_snmpv3
        ;;
    trap)
        send_trap
        ;;
    *)
        echo "Error: Invalid mode. Use discover, test, or trap."
        usage
        ;;
esac

echo "Operation completed."
exit 0 