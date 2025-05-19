#!/bin/bash
# Script to set up a container for testing Huawei MIB resolution with proper SNMPv3 authentication

echo "===== Setting Up MIB Testing Environment ====="

# Create directories
mkdir -p ./mib-test/mibs
mkdir -p ./mib-test/config

# 1. Copy MIB files to test directory
echo "1. Copying MIB files..."
cp -f fluentd-snmp/mibs/HW-IMAPV1NORTHBOUND-TRAP-MIB.mib ./mib-test/mibs/
cp -f fluentd-snmp/mibs/IMAP_NORTHBOUND_MIB-V1.mib ./mib-test/mibs/
cp -f fluentd-snmp/mibs/T2000-NETMANAGEMENT-MIB.mib ./mib-test/mibs/

# 2. Create snmptrapd configuration file with SHA-1 authentication
echo "2. Creating SNMPv3 configuration with SHA authentication..."

cat > ./mib-test/config/snmptrapd.conf << EOF
# SNMPv3 configuration
createUser -e 0x80001F88807C0F9A615F4B0768000000 NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata
authUser log,execute,net NCEadmin authPriv

# Accept SNMPv1/v2c traps
authCommunity log,execute,net public

# Disable authorization to accept all traps
disableAuthorization yes

# Verbose logging format
format1 TRAP: [%04y-%02m-%02d %02.2h:%02.2j:%02.2k] %B [%a] -> %b: %N::%W: %V
format2 TRAP: [%04y-%02m-%02d %02.2h:%02.2j:%02.2k] %B [%a] -> %b: %N::%W: %V
outputOption fts

# Log to file and stdout
logOption f,s /var/log/snmptrapd.log
EOF

# 3. Create SNMPv3 users file
cat > ./mib-test/config/snmpusers.conf << EOF
createUser -e 0x80001F88807C0F9A615F4B0768000000 NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata
EOF

# 4. Remove any existing container
if docker ps -q -f name=mib-test-container > /dev/null; then
    echo "Stopping existing container..."
    docker stop mib-test-container
fi

if docker ps -a -q -f name=mib-test-container > /dev/null; then
    echo "Removing existing container..."
    docker rm mib-test-container
fi

# 5. Start a temporary container to test MIB resolution
echo "3. Starting test container..."
docker run -d --name mib-test-container \
    -p 1164:1162/udp \
    -v $(pwd)/mib-test/mibs:/usr/share/snmp/mibs \
    -v $(pwd)/mib-test/config/snmptrapd.conf:/etc/snmp/snmptrapd.conf \
    -v $(pwd)/mib-test/config/snmpusers.conf:/var/lib/net-snmp/snmptrapd.conf \
    -e SNMPLIB_PERSISTENT_DIR=/var/lib/net-snmp \
    ubuntu:22.04 \
    sleep infinity

sleep 2

# 6. Install necessary packages in the container
echo "4. Installing SNMP packages in container..."
docker exec mib-test-container apt-get update
docker exec mib-test-container apt-get install -y snmp snmptrapd snmp-mibs-downloader

# 7. Set permissions for SNMPv3 user file
docker exec mib-test-container chmod 600 /var/lib/net-snmp/snmptrapd.conf

# 8. Start snmptrapd in the container
echo "5. Starting snmptrapd service with MIB support..."
docker exec mib-test-container sh -c "export MIBDIRS=/usr/share/snmp/mibs && snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf 0.0.0.0:1162 &"

sleep 2

# 9. Verify snmptrapd is running
if docker exec mib-test-container pgrep snmptrapd > /dev/null; then
    echo "✅ snmptrapd is running!"
else
    echo "❌ Failed to start snmptrapd!"
    exit 1
fi

# 10. Send test traps to verify MIB resolution
echo -e "\n6. Sending test traps..."
TRAP_ID="HW-MIB-TEST-$(date +%s)"

echo "Sending trap with Huawei OIDs from HW-IMAPV1NORTHBOUND-TRAP-MIB..."
echo " - OID: 1.3.6.1.4.1.2011.2.15.1.7.1.1.1 (hwNmNorthboundNEName)"

snmptrap -v 3 -e 0x80001F88807C0F9A615F4B0768000000 -u NCEadmin -a SHA -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:1164 '' \
  1.3.6.1.6.3.1.1.5.1 \
  1.3.6.1.4.1.2011.2.15.1.7.1.1.1 s "TestNE-$TRAP_ID" 2>/dev/null

sleep 2

echo "Sending trap with IMAP OIDs from IMAP_NORTHBOUND_MIB-V1..."
echo " - OID: 1.3.6.1.4.1.2011.2.15.2.1.2.1.1.1.1 (iMAPNorthboundHeartbeatSystemLabel)"

snmptrap -v 3 -e 0x80001F88807C0F9A615F4B0768000000 -u NCEadmin -a SHA -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:1164 '' \
  1.3.6.1.6.3.1.1.5.1 \
  1.3.6.1.4.1.2011.2.15.2.1.2.1.1.1.1 s "System-$TRAP_ID" 2>/dev/null

sleep 2

# 11. Check log output to see if MIB names were resolved
echo -e "\n7. Checking if MIB names were resolved..."
TRAP_LOG=$(docker exec mib-test-container cat /var/log/snmptrapd.log)
echo "$TRAP_LOG"

# 12. Analyze the results
echo -e "\n8. Analysis results:"

# Check for HW-IMAPV1NORTHBOUND-TRAP-MIB resolution
if docker exec mib-test-container cat /var/log/snmptrapd.log | grep -q "hwNmNorthboundNEName"; then
    echo "✅ SUCCESS: hwNmNorthboundNEName from HW-IMAPV1NORTHBOUND-TRAP-MIB was properly resolved!"
    docker exec mib-test-container cat /var/log/snmptrapd.log | grep "hwNmNorthboundNEName"
else
    echo "❌ FAIL: hwNmNorthboundNEName was not resolved. Raw OID appears in the log."
    docker exec mib-test-container cat /var/log/snmptrapd.log | grep "1.3.6.1.4.1.2011.2.15.1.7.1.1.1" || echo "No matches found for this OID"
fi

# Check for IMAP_NORTHBOUND_MIB-V1 resolution
if docker exec mib-test-container cat /var/log/snmptrapd.log | grep -q "iMAPNorthboundHeartbeatSystemLabel"; then
    echo "✅ SUCCESS: iMAPNorthboundHeartbeatSystemLabel from IMAP_NORTHBOUND_MIB-V1 was properly resolved!"
    docker exec mib-test-container cat /var/log/snmptrapd.log | grep "iMAPNorthboundHeartbeatSystemLabel"
else
    echo "❌ FAIL: iMAPNorthboundHeartbeatSystemLabel was not resolved. Raw OID appears in the log."
    docker exec mib-test-container cat /var/log/snmptrapd.log | grep "1.3.6.1.4.1.2011.2.15.2.1.2.1.1.1.1" || echo "No matches found for this OID"
fi

echo -e "\nIf you see symbolic MIB names (like hwNmNorthboundNEName) instead of numeric OIDs,"
echo "then the MIB files are being properly loaded and used."
echo "If you only see numeric OIDs (like 1.3.6.1.4.1.2011...), then there's an issue with MIB loading."
echo -e "\n===== Test Completed =====" 