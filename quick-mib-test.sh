#!/bin/bash
# Quick test for MIB loading and SNMPv3 trap handling

echo "===== Quick MIB Test Script ====="

# Force restart of container
echo "1. Restarting container..."
docker restart fluentd-snmp-trap
sleep 5

# Check if MIB files are loaded
echo "2. Checking MIB files..."
docker exec fluentd-snmp-trap ls -la /usr/share/snmp/mibs/ | grep -E "HW-|IMAP_"

# Start snmptrapd if needed
echo "3. Ensuring snmptrapd is running..."
if ! docker exec fluentd-snmp-trap pgrep snmptrapd > /dev/null; then
  echo "Starting snmptrapd..."
  docker exec fluentd-snmp-trap sh -c "snmptrapd -c /etc/snmp/snmptrapd.conf -Lf /var/log/snmptrapd.log -p /var/run/snmptrapd.pid -f &"
  sleep 2
fi

# Test sending a trap
echo "4. Sending test trap..."
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fluentd-snmp-trap)
TRAP_ID="TEST-$(date +%s)"

echo "Target: $CONTAINER_IP:1162"
snmptrap -v 3 -e 0x80001F88807C0F9A615F4B0768000000 -u NCEadmin -a SHA -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv "$CONTAINER_IP:1162" '' \
  1.3.6.1.4.1.2011.2.15.1.7.1.0.1 \
  1.3.6.1.4.1.2011.2.15.1.7.1.1.0 s "Test NE Name" \
  1.3.6.1.4.1.2011.2.15.1.7.1.2.0 s "Test NE Type" \
  1.3.6.1.4.1.2011.2.15.1.7.1.3.0 s "$TRAP_ID" 2>/dev/null

sleep 3

# Check log file
echo "5. Checking log file for trap..."
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -20

# Done
echo "===== Test Complete =====" 