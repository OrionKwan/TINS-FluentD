#!/bin/bash
# Direct test to bypass SNMPv3 issues

# Test V2C trap first to verify basic functionality
echo "Testing V2C trap..."
snmptrap -v 2c -c public localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "TEST-V2C-DIRECT" 2>/dev/null
sleep 2

# Check if V2C trap was received
echo "Checking V2C trap reception..."
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5 | grep TEST-V2C-DIRECT && echo "V2C trap received!"

# Add a direct log entry to test fluentd processing
echo "Adding direct log entry to test fluentd processing..."
docker exec fluentd-snmp-trap sh -c 'echo "SNMPTRAP: $(date) DIRECT-TEST 123" >> /var/log/snmptrapd.log'
sleep 1

# Check fluentd logs to see if it's processing
echo "Checking fluentd logs for message forwarding..."
docker logs fluentd-snmp-trap --tail 5 | grep -i "message"

echo "Testing direct UDP forwarding..."
echo "<snmp_trap><timestamp>$(date)</timestamp><test>direct</test><data>Testing UDP output to 165.202.6.129:1237</data></snmp_trap>" | nc -u 165.202.6.129 1237
echo "Direct message sent to 165.202.6.129:1237" 