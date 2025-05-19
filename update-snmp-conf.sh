#!/bin/bash
# Script to update snmptrapd.conf in the container

cat > snmptrapd-update.conf << 'EOF'
# SNMPv3 configuration
createUser -e 0x80001F88807C0F9A615F4B0768000000 NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
authUser log,execute,net NCEadmin authPriv

# Accept SNMPv1/v2c traps with community string
authCommunity log,execute,net public

# Disable authorization to accept all traps
disableAuthorization yes

# Format and log options
logOption f,s /var/log/snmptrapd.log

# Use our formatter script for all incoming traps
traphandle default /usr/local/bin/format-trap.sh
EOF

# Upload the file to the container
docker cp snmptrapd-update.conf fluentd-snmp-fixed:/etc/snmp/snmptrapd.conf

# Restart snmptrapd in the container
docker exec fluentd-snmp-fixed sh -c "killall snmptrapd && sleep 1 && /usr/sbin/snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf -p /var/run/snmptrapd.pid 0.0.0.0:1162 &"

# Verify the daemon is running
docker exec fluentd-snmp-fixed ps -ef | grep snmptrapd

echo "Configuration updated and snmptrapd restarted." 