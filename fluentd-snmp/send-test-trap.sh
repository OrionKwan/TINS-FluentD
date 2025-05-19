#!/bin/bash
# Unified SNMP trap sending script for both v2c and v3

# Default values
HOST="localhost"
PORT="1162"
COMMUNITY="public"
VERSION="2c"
USER="NCEadmin"
AUTH_PROTO="SHA"
AUTH_PASS="P@ssw0rdauth"
PRIV_PROTO="AES"
PRIV_PASS="P@ssw0rddata"
MESSAGE="Test SNMP trap message at $(date)"

# Help function
usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -h HOST       Target host (default: $HOST)"
  echo "  -p PORT       Target port (default: $PORT)"
  echo "  -v VERSION    SNMP version: 2c or 3 (default: $VERSION)"
  echo "  -c COMMUNITY  Community string for v2c (default: $COMMUNITY)"
  echo "  -u USER       SNMPv3 username (default: $USER)"
  echo "  -a AUTH       SNMPv3 auth protocol: MD5 or SHA (default: $AUTH_PROTO)"
  echo "  -A AUTHPASS   SNMPv3 auth password (default: $AUTH_PASS)"
  echo "  -x PRIV       SNMPv3 privacy protocol: DES or AES (default: $PRIV_PROTO)"
  echo "  -X PRIVPASS   SNMPv3 privacy password (default: $PRIV_PASS)"
  echo "  -m MESSAGE    Custom trap message (default: timestamp)"
  echo "  --help        Show this help message"
  exit 1
}

# Parse command line arguments
while [ "$1" != "" ]; do
  case $1 in
    -h)          shift; HOST=$1 ;;
    -p)          shift; PORT=$1 ;;
    -v)          shift; VERSION=$1 ;;
    -c)          shift; COMMUNITY=$1 ;;
    -u)          shift; USER=$1 ;;
    -a)          shift; AUTH_PROTO=$1 ;;
    -A)          shift; AUTH_PASS=$1 ;;
    -x)          shift; PRIV_PROTO=$1 ;;
    -X)          shift; PRIV_PASS=$1 ;;
    -m)          shift; MESSAGE=$1 ;;
    --help)      usage ;;
    *)           echo "Unknown option: $1"; usage ;;
  esac
  shift
done

# Validate SNMP version
if [ "$VERSION" != "2c" ] && [ "$VERSION" != "3" ]; then
  echo "Error: SNMP version must be 2c or 3"
  usage
fi

echo "Sending SNMP trap to $HOST:$PORT using SNMPv$VERSION"

# Send SNMP trap based on version
if [ "$VERSION" = "2c" ]; then
  # SNMPv2c trap
  echo "Sending SNMPv2c trap with community '$COMMUNITY'"
  snmptrap -v 2c -c "$COMMUNITY" "$HOST:$PORT" "" NET-SNMP-EXAMPLES-MIB::netSnmpExampleHeartbeatNotification netSnmpExampleHeartbeatRate i 123456 "s" "$MESSAGE"
else
  # SNMPv3 trap
  echo "Sending SNMPv3 trap with user '$USER'"
  snmptrap -v 3 -n "" -u "$USER" -a "$AUTH_PROTO" -A "$AUTH_PASS" -x "$PRIV_PROTO" -X "$PRIV_PASS" -l authPriv "$HOST:$PORT" "" NET-SNMP-EXAMPLES-MIB::netSnmpExampleHeartbeatNotification netSnmpExampleHeartbeatRate i 123456 "s" "$MESSAGE"
fi

# Check result
if [ $? -eq 0 ]; then
  echo "SNMP trap sent successfully!"
else
  echo "Failed to send SNMP trap"
  exit 1
fi 