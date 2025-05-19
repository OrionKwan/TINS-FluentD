#!/bin/sh
# Create required directories
mkdir -p /var/lib/net-snmp /etc/snmp

# Copy config files
cat /tmp/snmptrapd-users.conf > /var/lib/net-snmp/snmptrapd.conf
cat /tmp/snmptrapd-fixed.conf > /etc/snmp/snmptrapd.conf

# Set permissions
chmod 600 /var/lib/net-snmp/snmptrapd.conf
chmod 644 /etc/snmp/snmptrapd.conf

# Report success
echo "Configuration files updated successfully"
