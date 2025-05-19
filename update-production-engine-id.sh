#!/bin/bash
# Script to update the production fluentd-snmp container to use IP-based Engine ID

# Convert IP to Engine ID format
IP="172.29.36.80"
IP_HEX=$(printf '%02X%02X%02X%02X' $(echo $IP | tr '.' ' '))
ENGINE_ID="0x80000000c001${IP_HEX}"  # Standard prefix + IP in hex

echo "===== Updating fluentd-snmp to use IP-based Engine ID ====="
echo "IP Address: $IP"
echo "IP in Hex: $IP_HEX"
echo "Engine ID: $ENGINE_ID"

# 1. Create updated configuration files
echo "1. Creating updated configuration files..."

# Updated snmptrapd.conf
cat > /tmp/ip-snmptrapd.conf << EOF
# SNMPv3 configuration with IP-based Engine ID
createUser -e $ENGINE_ID NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata
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
EOF

# 2. Stop the production container
echo "2. Stopping fluentd-snmp-trap container..."
docker stop fluentd-snmp-trap

# 3. Copy the updated configuration to the container
echo "3. Updating container configuration..."
docker cp /tmp/ip-snmptrapd.conf fluentd-snmp-trap:/etc/snmp/snmptrapd.conf

# 4. Create updated user file inside the container
echo "4. Updating SNMPv3 user configuration inside container..."
docker start fluentd-snmp-trap
sleep 2
docker exec fluentd-snmp-trap sh -c "mkdir -p /var/lib/net-snmp && echo 'createUser -e $ENGINE_ID NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata' > /var/lib/net-snmp/snmptrapd.conf && chmod 600 /var/lib/net-snmp/snmptrapd.conf"

# 5. Update the container environment variable
echo "5. Setting Engine ID environment variable..."
# This is a demonstration. For permanent change, you should update your docker-compose.yml file.
docker stop fluentd-snmp-trap
docker run -d --name fluentd-snmp-trap-ip \
    -p 1162:1162/udp \
    -v $(pwd)/fluentd-snmp/mibs:/fluentd/mibs \
    -v $(pwd)/fluentd-snmp/conf:/fluentd/etc \
    -e SNMPV3_ENGINE_ID=$ENGINE_ID \
    --restart unless-stopped \
    fluentd-snmp-fixed

# 6. Display instructions for sending traps
echo -e "\n===== Update Complete ====="
echo "Your fluentd-snmp container is now configured with the IP-based Engine ID:"
echo "Engine ID: $ENGINE_ID"
echo
echo "To send traps to this container, use:"
echo "snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata -l authPriv <container_ip>:1162 ..."
echo
echo "To make this change permanent, update your docker-compose.yml file with:"
echo "    environment:"
echo "      - SNMPV3_ENGINE_ID=$ENGINE_ID" 