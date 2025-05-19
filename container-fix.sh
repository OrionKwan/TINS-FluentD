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
snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf 0.0.0.0:1162 &
sleep 2

# Report success
echo "SNMP configuration updated and service restarted"
