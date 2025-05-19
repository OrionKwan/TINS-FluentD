#!/bin/bash
# Script to fix SNMP Engine ID by setting the environment variable

echo "=== Fixing SNMPv3 Engine ID ==="

# Define the correct Engine ID
ENGINE_ID="0x80001F88807C0F9A615F4B0768000000"
echo "Using Engine ID: $ENGINE_ID"

# Update docker-compose.yml to include the Engine ID
echo "1. Updating docker-compose.yml with Engine ID..."
if grep -q "SNMPV3_ENGINE_ID" docker-compose.yml; then
  echo "Engine ID already set in docker-compose.yml"
else
  sed -i "/SNMPV3_PRIV_PROTOCOL=AES/a \ \ \ \ \ \ - SNMPV3_ENGINE_ID=$ENGINE_ID" docker-compose.yml
  echo "Added Engine ID to docker-compose.yml"
fi

# Stop the container
echo "2. Stopping the container..."
docker stop fluentd-snmp-trap

# Create a simple test script
echo "3. Creating test script..."
cat > test-engine-id.sh << EOT
#!/bin/bash
# Test script for SNMPv3 with the correct Engine ID

# Wait for the container to be ready
sleep 10

# Send a test trap
TEST_ID="FIXED-\$(date +%s)"
echo "Sending test SNMPv3 trap with Engine ID: $ENGINE_ID"
snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata \\
  -l authPriv localhost:1162 '' \\
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "\$TEST_ID"

sleep 3

# Check if the trap was received
echo "Checking if trap was received..."
if grep -q "\$TEST_ID" /var/log/snmptrapd.log; then
  echo "✅ SUCCESS: SNMPv3 trap was received!"
  grep "\$TEST_ID" /var/log/snmptrapd.log
else
  echo "❌ FAIL: SNMPv3 trap not found in log."
  echo "Last log entries:"
  tail -n 5 /var/log/snmptrapd.log
fi
EOT

# Start the container with the correct environment
echo "4. Starting container with Engine ID environment variable..."
docker-compose up -d fluentd-snmp

# Wait for the container to start
echo "5. Waiting for container to start..."
sleep 15

# Check if the container is running
echo "6. Checking if container is running..."
if docker ps | grep -q fluentd-snmp-trap; then
  echo "Container is running"
else
  echo "Container failed to start"
  docker logs fluentd-snmp-trap
  exit 1
fi

# Copy and run test script
echo "7. Copying test script to container..."
docker cp test-engine-id.sh fluentd-snmp-trap:/tmp/
docker exec fluentd-snmp-trap chmod +x /tmp/test-engine-id.sh

echo "8. Running test inside container..."
docker exec fluentd-snmp-trap /tmp/test-engine-id.sh

echo
echo "=== Engine ID Fix Completed ==="
echo "Your container should now be configured with the correct Engine ID."
echo "To send SNMPv3 traps to this container, use:"
echo "snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata -l authPriv localhost:1162 ..." 