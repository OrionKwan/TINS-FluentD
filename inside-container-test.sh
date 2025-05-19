#!/bin/bash
# Script to set up and test SNMPv3 from inside the container

echo "=== Testing SNMPv3 Inside Container ==="

# Create a test script to run inside the container
cat > inside-container.sh << 'EOF'
#!/bin/sh
set -e

# Create directories and fix permissions
mkdir -p /var/lib/snmp /var/lib/net-snmp
chmod -R 777 /var/lib/snmp /var/lib/net-snmp

# Clean any stale configs
rm -f /var/lib/snmp/snmpapp.conf /var/lib/net-snmp/snmptrapd.conf 2>/dev/null

# Create the SNMPv3 user directly in container
echo "Creating SNMPv3 user in container..."
cat > /etc/snmp/snmptrapd.conf << CONF
# Minimal SNMPv3 config
createUser NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
authUser log NCEadmin authPriv
disableAuthorization yes
CONF

echo "Killing existing snmptrapd..."
pkill -f snmptrapd || true
sleep 1

echo "Starting snmptrapd in debug mode..."
echo "Debug output will go to /var/log/snmptrapd-debug.log"
snmptrapd -Dusm,snmp,trap,debug -f -Lo -c /etc/snmp/snmptrapd.conf 0.0.0.0:1162 > /var/log/snmptrapd-debug.log 2>&1 &
sleep 2

# Generate a unique test ID for this test
TEST_ID="INSIDE-CONTAINER-$(date +%s)"
echo "Test ID: $TEST_ID"

# Create a test trap inside the container
echo "Sending test trap from inside container..."
snmptrap -v 3 -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID"

echo "Waiting for processing..."
sleep 2

# Check if the trap was received
echo "Checking if trap was logged..."
if grep -q "$TEST_ID" /var/log/snmptrapd.log; then
  echo "SUCCESS: SNMPv3 trap was received inside container!"
  grep "$TEST_ID" /var/log/snmptrapd.log
else
  echo "FAIL: SNMPv3 trap not found in log inside container."
  echo "Last 5 log entries:"
  tail -n 5 /var/log/snmptrapd.log
  echo "Debug log tail:"
  tail -n 20 /var/log/snmptrapd-debug.log
fi

echo "Test complete!"
EOF

# Copy script to container and make it executable
echo "Copying test script to container..."
docker cp inside-container.sh fluentd-snmp-trap:/inside-container.sh
docker exec fluentd-snmp-trap chmod +x /inside-container.sh

# Run the test inside the container
echo "Running test inside container..."
docker exec fluentd-snmp-trap /inside-container.sh

echo
echo "Test completed. Check the output above to see if SNMPv3 traps work inside the container." 