#!/bin/bash
# Script to test MIB translation directly

# Create a test container
docker run --name mib-test-direct -d -v $(pwd)/fluentd-snmp/mibs:/mibs ubuntu:22.04 sleep infinity

# Install required packages
docker exec mib-test-direct apt-get update
docker exec mib-test-direct apt-get install -y snmp snmp-mibs-downloader

# Try to translate MIB OIDs to numeric form
echo "Testing MIB translation..." > mib-test-results.txt
echo "----------------------------------------" >> mib-test-results.txt

echo "1. Testing HW-IMAPV1NORTHBOUND-TRAP-MIB..." >> mib-test-results.txt
docker exec mib-test-direct bash -c "export MIBS=ALL && export MIBDIRS=/mibs && snmptranslate -On HW-IMAPV1NORTHBOUND-TRAP-MIB::hwNmNorthboundNEName" >> mib-test-results.txt 2>&1
echo "" >> mib-test-results.txt

echo "2. Testing IMAP_NORTHBOUND_MIB-V1..." >> mib-test-results.txt
docker exec mib-test-direct bash -c "export MIBS=ALL && export MIBDIRS=/mibs && snmptranslate -On IMAP_NORTHBOUND_MIB-V1::iMAPNorthboundHeartbeatSystemLabel" >> mib-test-results.txt 2>&1
echo "" >> mib-test-results.txt

# Try reverse translation (numeric to symbolic)
echo "3. Testing reverse translation (numeric to symbolic)..." >> mib-test-results.txt
docker exec mib-test-direct bash -c "export MIBS=ALL && export MIBDIRS=/mibs && snmptranslate -Td 1.3.6.1.4.1.2011.2.15.1.7.1.1.1" >> mib-test-results.txt 2>&1
echo "" >> mib-test-results.txt

docker exec mib-test-direct bash -c "export MIBS=ALL && export MIBDIRS=/mibs && snmptranslate -Td 1.3.6.1.4.1.2011.2.15.2.1.2.1.1.1.1" >> mib-test-results.txt 2>&1
echo "" >> mib-test-results.txt

# Check if MIBs are being loaded at all
echo "4. Checking if MIBs are visible in the MIB path..." >> mib-test-results.txt
docker exec mib-test-direct bash -c "ls -la /mibs/" >> mib-test-results.txt 2>&1
echo "" >> mib-test-results.txt

echo "5. Testing standard MIB resolution for comparison..." >> mib-test-results.txt
docker exec mib-test-direct bash -c "export MIBS=ALL && snmptranslate -On SNMPv2-MIB::sysDescr" >> mib-test-results.txt 2>&1
echo "" >> mib-test-results.txt

echo "Done. Test results written to mib-test-results.txt"

# Clean up
docker stop mib-test-direct
docker rm mib-test-direct 