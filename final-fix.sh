#!/bin/bash
# Final fix script using a custom entrypoint

echo "=== Final SNMP Trap Container Fix ==="

# Stop and remove any existing container
echo "1. Stopping existing container..."
docker stop fluentd-snmp-trap || true
docker rm fluentd-snmp-trap || true

# Build the custom image
echo "2. Building custom image with fixed entrypoint..."
docker build -f Dockerfile.fixed -t fluentd-snmp-fixed .

# Run the container
echo "3. Running container with fixed entrypoint..."
docker run -d --name fluentd-snmp-trap \
  -p 1162:1162/udp \
  -v $(pwd)/fluentd-snmp/conf:/fluentd/etc:ro \
  -v $(pwd)/fluentd-snmp/plugins:/fluentd/plugins \
  -v $(pwd)/fluentd-snmp/mibs:/fluentd/mibs:ro \
  --network mvp-setup_opensearch-net \
  fluentd-snmp-fixed

# Wait for container to start
echo "4. Waiting for container to start..."
sleep 10

# Check container status
echo "5. Checking container status..."
if docker ps | grep -q fluentd-snmp-trap; then
  echo "Container is running"
else
  echo "Container failed to start"
  docker logs fluentd-snmp-trap
  exit 1
fi

# Test sending a trap
echo "6. Testing SNMPv3 trap reception..."
ENGINE_ID="172.29.36.80"
TEST_ID="FINAL-FIX-$(date +%s)"

docker exec fluentd-snmp-trap snmptrap -v 3 \
  -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID"

# Wait for processing
sleep 3

# Check if trap was received
echo "7. Checking if trap was received..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap was received!"
  echo "Log entry:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID"
else
  echo "❌ FAIL: SNMPv3 trap was not received."
  echo "Last log entries:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5
fi

echo
echo "=== Final Fix Completed ==="
echo "To send SNMPv3 traps to this container, use:"
echo "snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata -l authPriv localhost:1162 ..." 