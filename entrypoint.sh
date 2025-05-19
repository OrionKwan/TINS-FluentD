#!/bin/sh
set -e

# Kill any existing snmptrapd processes
killall snmptrapd tcpdump 2>/dev/null || true
sleep 1

# Create log directories and files
mkdir -p /var/log /fluentd/log
touch /var/log/snmptrapd.log /fluentd/log/fluentd.log /fluentd/log/error_$(date +%Y%m%d).log
chmod 666 /var/log/snmptrapd.log /fluentd/log/fluentd.log /fluentd/log/error_$(date +%Y%m%d).log

# Setup MIB directories
mkdir -p /usr/share/snmp/mibs
# Copy custom MIBs from our mibs directory to the system MIB directory
if [ -d /fluentd/mibs ] && [ "$(ls -A /fluentd/mibs)" ]; then
  echo "Copying custom MIB files..."
  cp -f /fluentd/mibs/* /usr/share/snmp/mibs/
  echo "MIB files copied"
fi

# Use environment variables for SNMP configuration (provided by docker-compose.yml)
SNMPV3_USER=${SNMPV3_USER:-NCEadmin}
SNMPV3_AUTH_PROTOCOL=${SNMPV3_AUTH_PROTOCOL:-SHA}
SNMPV3_AUTH_PASS=${SNMPV3_AUTH_PASS:-P@ssw0rdauth}
SNMPV3_PRIV_PROTOCOL=${SNMPV3_PRIV_PROTOCOL:-AES}
SNMPV3_PRIV_PASS=${SNMPV3_PRIV_PASS:-P@ssw0rddata}
SNMPV3_ENGINE_ID=${SNMPV3_ENGINE_ID:-}
SNMPV3_ENGINE_ID_HEX=${SNMPV3_ENGINE_ID_HEX:-}

# Log the configuration
echo "Using SNMP configuration from environment variables:"
echo "User: $SNMPV3_USER"
echo "Auth Protocol: $SNMPV3_AUTH_PROTOCOL"
echo "Priv Protocol: $SNMPV3_PRIV_PROTOCOL"
if [ -n "$SNMPV3_ENGINE_ID_HEX" ]; then
  echo "Engine ID (Hex): $SNMPV3_ENGINE_ID_HEX"
elif [ -n "$SNMPV3_ENGINE_ID" ]; then
  echo "Engine ID: $SNMPV3_ENGINE_ID"
else
  echo "Engine ID: Not specified (using default)"
fi

# Create a brand new SNMPv3 configuration file instead of trying to modify a read-only mounted file
mkdir -p /var/lib/net-snmp

# Create the complete configuration file with all necessary directives
cat > /etc/snmp/snmptrapd.conf << CONF
# SNMPv3 configuration - automatically generated
# Do not edit manually - changes will be lost

CONF

# Add the SNMPv3 user with engine ID
if [ -n "$SNMPV3_ENGINE_ID_HEX" ]; then
  echo "# Using specified hex Engine ID: $SNMPV3_ENGINE_ID_HEX" >> /etc/snmp/snmptrapd.conf
  echo "createUser -e $SNMPV3_ENGINE_ID_HEX $SNMPV3_USER $SNMPV3_AUTH_PROTOCOL $SNMPV3_AUTH_PASS $SNMPV3_PRIV_PROTOCOL $SNMPV3_PRIV_PASS" >> /etc/snmp/snmptrapd.conf
elif [ -n "$SNMPV3_ENGINE_ID" ] && echo "$SNMPV3_ENGINE_ID" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' > /dev/null; then
  ENGINE_ID_HEX="0x8000$(echo $SNMPV3_ENGINE_ID | awk -F. '{printf "%02x%02x%02x%02x", $1, $2, $3, $4}')"
  echo "# Engine ID for $SNMPV3_ENGINE_ID converted to hex format: $ENGINE_ID_HEX" >> /etc/snmp/snmptrapd.conf
  echo "createUser -e $ENGINE_ID_HEX $SNMPV3_USER $SNMPV3_AUTH_PROTOCOL $SNMPV3_AUTH_PASS $SNMPV3_PRIV_PROTOCOL $SNMPV3_PRIV_PASS" >> /etc/snmp/snmptrapd.conf
elif [ -n "$SNMPV3_ENGINE_ID" ]; then
  echo "# Using provided Engine ID: $SNMPV3_ENGINE_ID" >> /etc/snmp/snmptrapd.conf
  echo "createUser -e $SNMPV3_ENGINE_ID $SNMPV3_USER $SNMPV3_AUTH_PROTOCOL $SNMPV3_AUTH_PASS $SNMPV3_PRIV_PROTOCOL $SNMPV3_PRIV_PASS" >> /etc/snmp/snmptrapd.conf
else
  echo "# No Engine ID specified - using default" >> /etc/snmp/snmptrapd.conf
  echo "createUser $SNMPV3_USER $SNMPV3_AUTH_PROTOCOL $SNMPV3_AUTH_PASS $SNMPV3_PRIV_PROTOCOL $SNMPV3_PRIV_PASS" >> /etc/snmp/snmptrapd.conf
fi

# Add the complete configuration
cat >> /etc/snmp/snmptrapd.conf << CONF

# SNMPv3 auth rules
authUser log,execute,net $SNMPV3_USER authPriv
authUser log,execute,net $SNMPV3_USER authNoPriv
authUser log,execute,net $SNMPV3_USER noauth

# Community strings for SNMPv1/v2c
authCommunity log,execute,net public

# Trap format and logging options
format1 TRAP: %B [%a] -> %b: %N::%W: %V
outputOption f

# Required options for trap handling
disableAuthorization yes

# Use special script to format trap data
traphandle default /usr/local/bin/format-trap.sh
CONF

# Set proper permissions
chmod 644 /etc/snmp/snmptrapd.conf

# Log the final configuration for debugging
echo "Final SNMPv3 configuration:"
head -10 /etc/snmp/snmptrapd.conf

# Create a script to process trap data with formatting for web applications
cat > /usr/local/bin/format-trap.sh << 'SCRIPT'
#!/bin/sh
# Script to receive trap data and format it with XML-like tags for web application
while read line; do
  if [ -n "$line" ]; then
    # Format timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Format the trap data with XML-like tags
    formatted_data="<trap><timestamp>$timestamp</timestamp><data>$line</data></trap>"
    
    # Log both the original and formatted data
    echo "SNMPTRAP: $timestamp $line" >> /var/log/snmptrapd.log
    echo "FORMATTED: $formatted_data" >> /var/log/snmptrapd.log
  fi
done
SCRIPT
chmod +x /usr/local/bin/format-trap.sh

# Create a special raw packet handler script
cat > /usr/local/bin/log-raw-packet.sh << 'SCRIPT'
#!/bin/sh
# Script to log raw packet data
while read line; do
  if [ -n "$line" ]; then
    # Format timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log raw packet data
    echo "RAW_PACKET: $timestamp $line" >> /var/log/snmptrapd.log
  fi
done
SCRIPT
chmod +x /usr/local/bin/log-raw-packet.sh

# Add initialization message to log
echo "SNMPTRAP: $(date '+%Y-%m-%d %H:%M:%S') Trap listener initialized with custom MIB support" > /var/log/snmptrapd.log

# Start snmptrapd in foreground mode with all MIBs with debug output
echo "Starting snmptrapd with MIB support..."
# Set environment variable to include custom MIBs
export MIBDIRS=/usr/share/snmp/mibs

# Check if a specific network interface is being used for SNMP 
if [ -n "$SNMP_BIND_INTERFACE" ]; then
  # Get the IP address of the specified interface
  BIND_IP=$(ip -4 addr show $SNMP_BIND_INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  if [ -n "$BIND_IP" ]; then
    echo "Binding snmptrapd to $SNMP_BIND_INTERFACE ($BIND_IP)"
    # Start snmptrapd bound to the specific interface
    /usr/sbin/snmptrapd -f -c /etc/snmp/snmptrapd.conf -p /var/run/snmptrapd.pid -n $BIND_IP:1162 >> /var/log/snmptrapd.log 2>&1 &
  else
    echo "WARNING: Could not determine IP for interface $SNMP_BIND_INTERFACE, using default binding"
    /usr/sbin/snmptrapd -f -c /etc/snmp/snmptrapd.conf -p /var/run/snmptrapd.pid 0.0.0.0:1162 >> /var/log/snmptrapd.log 2>&1 &
  fi
else
  # Start snmptrapd bound to all interfaces
  /usr/sbin/snmptrapd -f -c /etc/snmp/snmptrapd.conf -p /var/run/snmptrapd.pid 0.0.0.0:1162 >> /var/log/snmptrapd.log 2>&1 &
fi

# Give snmptrapd time to start
sleep 2

# Check if snmptrapd is running
if pgrep snmptrapd > /dev/null; then
  echo "snmptrapd is running successfully with MIB support"
else
  echo "ERROR: snmptrapd failed to start"
  exit 1
fi

# Run Fluentd
echo "Starting Fluentd..."
exec "$@" 