#!/bin/bash
# Final test to check if MIB files can be properly parsed

echo "=== Testing Huawei MIB Files ===" > mib-test-report.txt

# 1. Create a temporary container for testing
container_id=$(docker run -d -v $(pwd)/fluentd-snmp/mibs:/mibs ubuntu:22.04 sleep infinity)
echo "Created test container: $container_id" >> mib-test-report.txt

# 2. Install SNMP tools
echo "Installing SNMP tools..." >> mib-test-report.txt
docker exec $container_id apt-get update -qq
docker exec $container_id apt-get install -y -qq snmp

# 3. Test if MIBs can be loaded using mib2c tool
echo "Testing MIB file parsing..." >> mib-test-report.txt
docker exec $container_id sh -c "ls -la /mibs/" >> mib-test-report.txt

# 4. Test import of each MIB file
echo -e "\nTesting HW-IMAPV1NORTHBOUND-TRAP-MIB.mib..." >> mib-test-report.txt
docker exec $container_id sh -c "export MIBS=ALL && export MIBDIRS=/mibs && snmptranslate -M /mibs -m /mibs/HW-IMAPV1NORTHBOUND-TRAP-MIB.mib -IR hwNmNorthboundNEName 2>&1" >> mib-test-report.txt

echo -e "\nTesting IMAP_NORTHBOUND_MIB-V1.mib..." >> mib-test-report.txt
docker exec $container_id sh -c "export MIBS=ALL && export MIBDIRS=/mibs && snmptranslate -M /mibs -m /mibs/IMAP_NORTHBOUND_MIB-V1.mib -IR iMAPNorthboundHeartbeatSystemLabel 2>&1" >> mib-test-report.txt

# 5. Check if specific OIDs can be found by their numeric value
echo -e "\nTesting OID resolution by numeric value..." >> mib-test-report.txt
docker exec $container_id sh -c "export MIBS=ALL && export MIBDIRS=/mibs && snmptranslate -M /mibs -m ALL 1.3.6.1.4.1.2011.2.15.1.7.1.1.1 2>&1" >> mib-test-report.txt
docker exec $container_id sh -c "export MIBS=ALL && export MIBDIRS=/mibs && snmptranslate -M /mibs -m ALL 1.3.6.1.4.1.2011.2.15.2.1.2.1.1.1.1 2>&1" >> mib-test-report.txt

# 6. Make a SNMP request with the MIB
echo -e "\nAttempting to create a SNMP trap with the MIB..." >> mib-test-report.txt
docker exec $container_id sh -c "export MIBS=ALL && export MIBDIRS=/mibs && snmptrap -v 2c -c public localhost '' HW-IMAPV1NORTHBOUND-TRAP-MIB::hwNmNorthboundNEName s 'test' 2>&1 || echo 'Failed to create trap'" >> mib-test-report.txt

# 7. Cleanup
docker stop $container_id > /dev/null
docker rm $container_id > /dev/null
echo -e "\nTest complete. Results saved to mib-test-report.txt" 