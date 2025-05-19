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
echo "Available MIB files:"
ls -la /usr/share/snmp/mibs/

# Create snmp.conf to set MIB loading parameters
cat > /etc/snmp/snmp.conf << EOF
# Set MIB paths and loading options
mibdirs /usr/share/snmp/mibs
mibs ALL
EOF
chmod 644 /etc/snmp/snmp.conf

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

# Use the template from the mounted volume
echo "Using SNMPv3 configuration template from /fluentd/etc/snmptrapd.conf"
cp /fluentd/etc/snmptrapd.conf /etc/snmp/snmptrapd.conf
chmod 644 /etc/snmp/snmptrapd.conf

# Add initialization message to log
echo "SNMPTRAP: $(date '+%Y-%m-%d %H:%M:%S') Trap listener initialized with custom MIB support" > /var/log/snmptrapd.log
chmod 666 /var/log/snmptrapd.log

# Start snmptrapd in foreground mode with all MIBs
echo "Starting snmptrapd with MIB support..."
# Set environment variable to include custom MIBs
export MIBDIRS=/usr/share/snmp/mibs
export MIBS=ALL

# Check if a specific network interface is being used for SNMP 
if [ -n "$SNMP_BIND_INTERFACE" ]; then
  # Get the IP address of the specified interface (avoid using grep -P)
  BIND_IP=$(ip -4 addr show $SNMP_BIND_INTERFACE | grep -E 'inet [0-9.]+' | awk '{print $2}' | cut -d/ -f1)
  if [ -n "$BIND_IP" ]; then
    echo "Binding snmptrapd to $SNMP_BIND_INTERFACE ($BIND_IP)"
    # Start snmptrapd bound to the specific interface with log output
    /usr/sbin/snmptrapd -f -Lf /var/log/snmptrapd.log -c /etc/snmp/snmptrapd.conf -p /var/run/snmptrapd.pid -n $BIND_IP:1162 2>&1 &
  else
    echo "WARNING: Could not determine IP for interface $SNMP_BIND_INTERFACE, using default binding"
    /usr/sbin/snmptrapd -f -Lf /var/log/snmptrapd.log -c /etc/snmp/snmptrapd.conf -p /var/run/snmptrapd.pid 0.0.0.0:1162 2>&1 &
  fi
else
  # Start snmptrapd bound to all interfaces
  /usr/sbin/snmptrapd -f -Lf /var/log/snmptrapd.log -c /etc/snmp/snmptrapd.conf -p /var/run/snmptrapd.pid 0.0.0.0:1162 2>&1 &
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

# Run Fluentd
echo "Starting Fluentd..."
exec "$@"