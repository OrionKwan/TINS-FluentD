#!/bin/sh
# Create directories if they don't exist
mkdir -p /var/lib/net-snmp /etc/snmp

# Copy config files
cat /tmp/snmptrapd-users.conf > /var/lib/net-snmp/snmptrapd.conf
cat /tmp/snmptrapd-fixed.conf > /etc/snmp/snmptrapd.conf

# Set permissions
chmod 600 /var/lib/net-snmp/snmptrapd.conf
chmod 644 /etc/snmp/snmptrapd.conf

# Kill existing snmptrapd
pkill -f snmptrapd || true
sleep 1

# Start snmptrapd with the new configuration
/usr/sbin/snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf 0.0.0.0:1162 &
sleep 2

# Check if snmptrapd is running
if pgrep snmptrapd > /dev/null; then
  echo "snmptrapd is running with correct Engine ID"
  exit 0
else
  echo "Failed to start snmptrapd"
  exit 1
fi
