#!/bin/sh
set -e

# Kill any existing snmptrapd processes
killall snmptrapd tcpdump 2>/dev/null || true
sleep 1

# Create log directory and file
mkdir -p /var/log
touch /var/log/snmptrapd.log
chmod 666 /var/log/snmptrapd.log

# Setup MIB directories
mkdir -p /usr/share/snmp/mibs
# Copy custom MIBs from our mibs directory to the system MIB directory
if [ -d /fluentd/mibs ] && [ "$(ls -A /fluentd/mibs)" ]; then
  echo "Copying custom MIB files..."
  cp -f /fluentd/mibs/* /usr/share/snmp/mibs/
  echo "MIB files copied"
fi

# Define the hardcoded Engine ID
ENGINE_ID="172.29.36.80"
echo "Using fixed Engine ID: $ENGINE_ID"

# Create SNMPv3 user directly in the persistent configuration
mkdir -p /var/lib/net-snmp
cat > /var/lib/net-snmp/snmptrapd.conf << CONF
createUser -e $ENGINE_ID NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
CONF
chmod 600 /var/lib/net-snmp/snmptrapd.conf

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

# Create snmptrapd.conf with hardcoded Engine ID
cat > /etc/snmp/snmptrapd.conf << CONF
# SNMPv3 configuration with fixed Engine ID
createUser -e $ENGINE_ID NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
authUser log,execute,net NCEadmin authPriv

# Accept SNMPv1/v2c traps with community string
authCommunity log,execute,net public

# Disable authorization to accept all traps
disableAuthorization yes

# Use formatter script for all incoming traps
traphandle default /usr/local/bin/format-trap.sh
CONF

# Add initialization message to log
echo "SNMPTRAP: $(date '+%Y-%m-%d %H:%M:%S') Trap listener initialized with fixed Engine ID $ENGINE_ID" > /var/log/snmptrapd.log

# Start snmptrapd in foreground mode with all MIBs
echo "Starting snmptrapd with MIB support..."
# Set environment variable to include custom MIBs
export MIBDIRS=/usr/share/snmp/mibs
/usr/sbin/snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf -p /var/run/snmptrapd.pid 0.0.0.0:1162 &

# Give snmptrapd time to start
sleep 2

# Check if snmptrapd is running
if pgrep snmptrapd > /dev/null; then
  echo "snmptrapd is running successfully with MIB support"
else
  echo "ERROR: snmptrapd failed to start"
  exit 1
fi

# Run a test trap to verify configuration
TEST_ID="STARTUP-TEST-$(date +%s)"
echo "Sending test trap to verify configuration..."
snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID"

sleep 2

# Check if the test trap was received
if grep -q "$TEST_ID" /var/log/snmptrapd.log; then
  echo "SUCCESS: Test trap was received internally"
else
  echo "WARNING: Test trap was not received"
fi

# Run Fluentd
echo "Starting Fluentd..."
exec "$@" 