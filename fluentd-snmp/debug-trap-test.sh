#!/bin/bash
# Debug script to test SNMPv3 trap reception with verbose output

TRAP_ID="DEBUG-$(date +%s)"
echo "======== DEBUGGING SNMP TRAP RECEPTION ========"

# Check if snmptrapd is running in the container
echo "1. Checking if snmptrapd is running:"
docker exec fluentd-snmp-trap ps aux | grep -v grep | grep snmptrapd || echo "SNMPTRAPD NOT RUNNING"

# Check container IP and ports
echo "2. Checking container network:"
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fluentd-snmp-trap

# Check MIB path and files 
echo "3. Checking MIB files:"
docker exec fluentd-snmp-trap ls -la /usr/share/snmp/mibs/

# Check snmptrapd configuration
echo "4. Checking snmptrapd configuration:"
docker exec fluentd-snmp-trap cat /etc/snmp/snmptrapd.conf | grep -v "^#" | grep -v "^$"

# Send a test trap with verbose output
echo "5. Sending test trap with ID: $TRAP_ID"
snmptrap -v 3 -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv -u NCEadmin -e 0x80001F88807C0F9A615F4B0768000000 \
  -d "192.168.8.100:1162" "" \
  1.3.6.1.6.3.1.1.5.4 \
  1.3.6.1.2.1.1.5.0 s "$TRAP_ID" 2>&1

echo "6. Waiting 5 seconds for processing..."
sleep 5

# Check if trap was received
echo "7. Checking log file for trap receipt:"
docker exec fluentd-snmp-trap grep -A 3 "$TRAP_ID" /var/log/snmptrapd.log || (
  echo "8. Trap not found. Last 10 log entries:" 
  docker exec fluentd-snmp-trap tail -10 /var/log/snmptrapd.log
)

echo "======== DEBUG COMPLETE ========" 