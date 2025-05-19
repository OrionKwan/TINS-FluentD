#!/bin/bash
# Script to update the Engine ID to 172.29.36.80

echo "===== Updating Engine ID to 172.29.36.80 ====="

# 1. Convert IP to hexadecimal format
IP="172.29.36.80"
IP_HEX=$(printf '%02X%02X%02X%02X' $(echo $IP | tr '.' ' '))
ENGINE_ID="0x80000000c001${IP_HEX}"  # Standard prefix + IP in hex

echo "IP Address: $IP"
echo "IP in Hex: $IP_HEX"
echo "Engine ID: $ENGINE_ID"

# 2. Create snmptrapd configuration with the new Engine ID
cat > /tmp/updated-snmptrapd.conf << EOF
# SNMPv3 configuration
createUser -e $ENGINE_ID NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata
authUser log,execute,net NCEadmin authPriv

# Accept SNMPv1/v2c traps with community string
authCommunity log,execute,net public

# Disable authorization to accept all traps
disableAuthorization yes

# Verbose format for logging
format1 TRAP: [%04y-%02m-%02d %02.2h:%02.2j:%02.2k] %B [%a] -> %b: %N::%W: %V
format2 TRAP: [%04y-%02m-%02d %02.2h:%02.2j:%02.2k] %B [%a] -> %b: %N::%W: %V
outputOption fts

# Log to file and stdout
logOption f,s /var/log/snmptrapd.log
EOF

# 3. Create directory for container configuration
mkdir -p ./engine-id-test/mibs
mkdir -p ./engine-id-test/config

# 4. Copy MIB files to test directory
echo "Copying MIB files..."
cp -f fluentd-snmp/mibs/HW-IMAPV1NORTHBOUND-TRAP-MIB.mib ./engine-id-test/mibs/
cp -f fluentd-snmp/mibs/IMAP_NORTHBOUND_MIB-V1.mib ./engine-id-test/mibs/
cp -f fluentd-snmp/mibs/T2000-NETMANAGEMENT-MIB.mib ./engine-id-test/mibs/

# 5. Copy the configuration file
cp /tmp/updated-snmptrapd.conf ./engine-id-test/config/snmptrapd.conf

# 6. Create SNMPv3 users file for container
cat > ./engine-id-test/config/snmpusers.conf << EOF
createUser -e $ENGINE_ID NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata
EOF

# 7. Stop and remove any existing test container
if docker ps -q -f name=engine-id-test > /dev/null; then
    echo "Stopping existing container..."
    docker stop engine-id-test
fi

if docker ps -a -q -f name=engine-id-test > /dev/null; then
    echo "Removing existing container..."
    docker rm engine-id-test
fi

# 8. Start a new container with the updated configuration
echo "Starting test container with Engine ID: $ENGINE_ID"
docker run -d --name engine-id-test \
    -p 1165:1162/udp \
    -v $(pwd)/engine-id-test/mibs:/usr/share/snmp/mibs \
    -v $(pwd)/engine-id-test/config/snmptrapd.conf:/etc/snmp/snmptrapd.conf \
    -v $(pwd)/engine-id-test/config/snmpusers.conf:/var/lib/net-snmp/snmptrapd.conf \
    -e SNMPLIB_PERSISTENT_DIR=/var/lib/net-snmp \
    -e SNMPV3_ENGINE_ID=$ENGINE_ID \
    ubuntu:22.04 \
    sleep infinity

# 9. Install necessary packages
echo "Installing SNMP packages in container..."
docker exec engine-id-test apt-get update -qq
docker exec engine-id-test apt-get install -y -qq snmp snmptrapd snmp-mibs-downloader

# 10. Set permissions for SNMPv3 user file
docker exec engine-id-test chmod 600 /var/lib/net-snmp/snmptrapd.conf

# 11. Start snmptrapd in the container
echo "Starting snmptrapd service with Engine ID: $ENGINE_ID"
docker exec engine-id-test sh -c "export MIBDIRS=/usr/share/snmp/mibs && snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf 0.0.0.0:1162 &"

sleep 2

# 12. Verify snmptrapd is running
if docker exec engine-id-test pgrep snmptrapd > /dev/null; then
    echo "✅ snmptrapd is running with Engine ID: $ENGINE_ID"
else
    echo "❌ Failed to start snmptrapd!"
    exit 1
fi

# 13. Test the configuration
echo -e "\nTesting SNMPv3 trap with Engine ID: $ENGINE_ID"
echo "Sending test trap to localhost:1165 (mapped to container port 1162)"
TRAP_ID="IP-ENGINE-TEST-$(date +%s)"

snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a SHA -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:1165 '' \
  1.3.6.1.4.1.2011.2.15.1.7.1.0.1 \
  1.3.6.1.4.1.2011.2.15.1.7.1.1.1 s "TestNE-$TRAP_ID" 2>/dev/null

sleep 3

# 14. Check if trap was received
echo -e "\nChecking if trap was received..."

# Create a log file if it doesn't exist yet
docker exec engine-id-test sh -c "touch /var/log/snmptrapd.log"

# Grab the log content
LOG_CONTENT=$(docker exec engine-id-test cat /var/log/snmptrapd.log)

if echo "$LOG_CONTENT" | grep -q "$TRAP_ID"; then
    echo "✅ SUCCESS: Trap was received successfully!"
    docker exec engine-id-test grep "$TRAP_ID" /var/log/snmptrapd.log
else
    echo "❌ FAIL: Trap was not received or logged."
    echo "Recent log entries:"
    docker exec engine-id-test cat /var/log/snmptrapd.log || echo "No log file found"
fi

echo -e "\n===== Engine ID Update Complete ====="
echo "To use this Engine ID in your production container, update your docker-compose.yml or container startup script with:"
echo "SNMPV3_ENGINE_ID=$ENGINE_ID"
echo
echo "To send traps to this Engine ID, use:"
echo "snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata ..." 