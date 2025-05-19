#!/bin/bash
# Script to test if the Huawei MIB files are being properly loaded and resolved

echo "===== Testing Huawei MIB Files Translation ====="

# First ensure our modified container is running
if ! docker ps -q -f name=fluentd-snmp-modified > /dev/null; then
  echo "Container is not running. Starting or creating it..."
  ./run-modified-container.sh > /dev/null 2>&1
  sleep 5
fi

CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fluentd-snmp-modified)
echo "Target container IP: $CONTAINER_IP"
TRAP_PORT="1163"  # Port mapped to 1162 inside container

# Clear the snmptrapd log to make our test results clearer
docker exec fluentd-snmp-modified sh -c "cat /dev/null > /var/log/snmptrapd.log"

# 1. Send a trap using OIDs from HW-IMAPV1NORTHBOUND-TRAP-MIB
echo -e "\n1. Sending test trap using HW-IMAPV1NORTHBOUND-TRAP-MIB OIDs..."
TRAP_ID="HUAWEI-MIB-TEST-$(date +%s)"

echo "OID: 1.3.6.1.4.1.2011.2.15.1.7.1.1.1 (hwNmNorthboundNEName)"
echo "OID: 1.3.6.1.4.1.2011.2.15.1.7.1.1.2 (hwNmNorthboundNEType)"

# Send trap using Huawei OIDs
snmptrap -v 3 -e 0x80001F88807C0F9A615F4B0768000000 -u NCEadmin -a SHA -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:$TRAP_PORT '' \
  1.3.6.1.4.1.2011.2.15.1.7.1.0.1 \
  1.3.6.1.4.1.2011.2.15.1.7.1.1.1 s "TestNE-$TRAP_ID" \
  1.3.6.1.4.1.2011.2.15.1.7.1.1.2 s "Huawei-Router" 2>/dev/null

sleep 2

# 2. Send a trap using OIDs from IMAP_NORTHBOUND_MIB-V1
echo -e "\n2. Sending test trap using IMAP_NORTHBOUND_MIB-V1 OIDs..."
TRAP_ID2="IMAP-MIB-TEST-$(date +%s)"

echo "OID: 1.3.6.1.4.1.2011.2.15.2.1.2.1.1.1.1 (iMAPNorthboundHeartbeatSystemLabel)"
echo "OID: 1.3.6.1.4.1.2011.2.15.2.1.2.1.1.1.3 (iMAPNorthboundHeartbeatTimeStamp)"

# Send trap using IMAP OIDs
snmptrap -v 3 -e 0x80001F88807C0F9A615F4B0768000000 -u NCEadmin -a SHA -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:$TRAP_PORT '' \
  1.3.6.1.4.1.2011.2.15.2.1.2.1.1.1.0.1 \
  1.3.6.1.4.1.2011.2.15.2.1.2.1.1.1.1 s "System-$TRAP_ID2" \
  1.3.6.1.4.1.2011.2.15.2.1.2.1.1.1.3 s "$(date)" 2>/dev/null

sleep 2

# 3. Check if the trap was received and if MIB names were resolved
echo -e "\n3. Checking trap reception and MIB name resolution..."
echo "Trap log content:"
docker exec fluentd-snmp-modified cat /var/log/snmptrapd.log

# 4. Check specifically for MIB name resolution in the log
echo -e "\n4. Analyzing MIB name resolution results..."

# Check for HW-IMAPV1NORTHBOUND-TRAP-MIB resolution
if docker exec fluentd-snmp-modified grep -q "hwNmNorthboundNEName" /var/log/snmptrapd.log; then
  echo "✅ SUCCESS: hwNmNorthboundNEName from HW-IMAPV1NORTHBOUND-TRAP-MIB was properly resolved!"
  docker exec fluentd-snmp-modified grep "hwNmNorthboundNEName" /var/log/snmptrapd.log
else
  echo "❌ FAIL: hwNmNorthboundNEName was not resolved. Raw OID appears in the log."
  docker exec fluentd-snmp-modified grep "1.3.6.1.4.1.2011.2.15.1.7.1.1.1" /var/log/snmptrapd.log
fi

# Check for IMAP_NORTHBOUND_MIB-V1 resolution
if docker exec fluentd-snmp-modified grep -q "iMAPNorthboundHeartbeatSystemLabel" /var/log/snmptrapd.log; then
  echo "✅ SUCCESS: iMAPNorthboundHeartbeatSystemLabel from IMAP_NORTHBOUND_MIB-V1 was properly resolved!"
  docker exec fluentd-snmp-modified grep "iMAPNorthboundHeartbeatSystemLabel" /var/log/snmptrapd.log
else
  echo "❌ FAIL: iMAPNorthboundHeartbeatSystemLabel was not resolved. Raw OID appears in the log."
  docker exec fluentd-snmp-modified grep "1.3.6.1.4.1.2011.2.15.2.1.2.1.1.1.1" /var/log/snmptrapd.log
fi

echo -e "\nIf you see the MIB name in the log instead of numeric OIDs, the MIB files are being properly loaded and used!"
echo "If you only see numeric OIDs like 1.3.6.1.4.1.2011... then the MIBs aren't being properly loaded or parsed."
echo "===== Test Completed =====" 