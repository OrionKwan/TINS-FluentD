#!/bin/bash
# Script to properly fix the SNMPv3 configuration in both locations

echo "=== Fixing SNMPv3 configuration ==="

# Create the proper configuration with Engine ID
cat > snmptrapd-fixed.conf << EOF
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

# Create the persistent SNMPv3 user file
cat > snmp-users.conf << EOF
createUser -e 0x80001F88807C0F9A615F4B0768000000 NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
EOF

echo "1. Copying configuration files to container..."
docker cp snmptrapd-fixed.conf fluentd-snmp-trap:/etc/snmp/snmptrapd.conf
docker cp snmp-users.conf fluentd-snmp-trap:/var/lib/net-snmp/snmptrapd.conf

echo "2. Stopping snmptrapd..."
docker exec fluentd-snmp-trap killall snmptrapd 2>/dev/null || true
sleep 2

echo "3. Starting snmptrapd with fixed configuration..."
docker exec fluentd-snmp-trap sh -c "/usr/sbin/snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf -p /var/run/snmptrapd.pid 0.0.0.0:1162 &"
sleep 2

echo "4. Verifying snmptrapd is running..."
docker exec fluentd-snmp-trap ps -ef | grep snmptrapd

echo "5. Creating a new test file in the log..."
docker exec fluentd-snmp-trap sh -c "echo 'SNMPTRAP: $(date +%Y-%m-%d\ %H:%M:%S) Trap daemon restarted with Engine ID configuration' > /var/log/snmptrapd.log"

echo "=== SNMPv3 configuration fix complete ===" 