#!/bin/bash
# Script to update snmptrapd.conf and restart services

# Create new config
cat > new-snmptrapd.conf << EOF
# SNMPv3 configuration
createUser -e 0x80001F88807C0F9A615F4B0768000000 NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
authUser log,execute,net NCEadmin authPriv

# Accept SNMPv1/v2c traps with community string
authCommunity log,execute,net public

# Disable authorization to accept all traps
disableAuthorization yes

# Log format specification - more verbose
format1 TRAP: [%04y-%02m-%02d %02.2h:%02.2j:%02.2k] %B [%a] -> %b: %N::%W: %V
format2 TRAP: [%04y-%02m-%02d %02.2h:%02.2j:%02.2k] %B [%a] -> %b: %N::%W: %V
outputOption fts

# Log to file and stdout
logOption f,s /var/log/snmptrapd.log

# Use format script (if exists)
traphandle default /usr/local/bin/format-trap.sh
EOF

# Copy to container
echo "Updating snmptrapd.conf in container..."
docker cp new-snmptrapd.conf fluentd-snmp-trap:/etc/snmp/snmptrapd.conf

# Restart snmptrapd
echo "Restarting SNMP trap daemon..."
docker exec fluentd-snmp-trap sh -c "kill -9 \$(ps -ef | grep snmptrapd | grep -v grep | awk '{print \$1}')"
docker exec fluentd-snmp-trap sh -c "mkdir -p /var/run && /usr/sbin/snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf -p /var/run/snmptrapd.pid 0.0.0.0:1162 &"

echo "Waiting for snmptrapd to initialize..."
sleep 3

# Check if running
echo "Verifying snmptrapd is running..."
docker exec fluentd-snmp-trap ps -ef | grep -i snmptrapd

echo "Configuration update complete." 