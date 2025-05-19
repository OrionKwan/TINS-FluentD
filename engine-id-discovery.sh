#!/bin/bash
# Script to discover SNMP Engine ID in the fluentd-snmp container

echo "=== SNMP Engine ID Discovery Tool ==="
echo "This script will attempt to find the SNMPv3 Engine ID used by the container."
echo

# 1. Check if container is running
echo "1. Checking container status..."
if docker ps | grep -q fluentd-snmp-trap; then
  echo "✅ Container is running"
else
  echo "❌ Container not found. Please start it with: docker-compose up -d fluentd-snmp"
  exit 1
fi

# 2. Check for persistent configuration files
echo
echo "2. Looking for persistent configuration files..."
docker exec fluentd-snmp-trap find / -name snmpapp.conf -o -name snmptrapd.boot 2>/dev/null | while read file; do
  echo "Found: $file"
  docker exec fluentd-snmp-trap cat "$file" 2>/dev/null | grep -i engine
done

# 3. Attempt to find Engine ID from running process
echo
echo "3. Checking current configuration..."
docker exec fluentd-snmp-trap ps aux | grep snmptrapd

# 4. Try to debug snmptrapd
echo
echo "4. Running snmptrapd with debugging..."
docker exec fluentd-snmp-trap sh -c "snmptrapd -Dusm,config,9 -f 2>&1 | grep -i 'engine\|boot\|id'" || echo "No debug info available"

# 5. Create a test trap with embedded extraction of Engine ID
echo
echo "5. Creating an SNMPv3 test user for discovery..."
cat > test-snmpv3-user.conf << 'EOF'
createUser testuser SHA testpass1234 AES testkey5678
authUser log testuser
EOF

echo "Applying test configuration..."
cat test-snmpv3-user.conf | docker exec -i fluentd-snmp-trap tee /etc/snmp/temp-snmptrapd.conf > /dev/null

echo "Restarting snmptrapd with debug options..."
docker exec fluentd-snmp-trap sh -c "pkill -f snmptrapd; snmptrapd -f -c /etc/snmp/temp-snmptrapd.conf -Dusm,9 2>&1 | grep -i engine" &

# Wait for a moment to start up
sleep 5

echo
echo "6. Summary:"
echo "If you discovered the Engine ID, use it in your SNMPv3 trap sender with:"
echo "   snmptrap -v 3 -e 0xFOUND_ENGINE_ID -u NCEadmin ... localhost:1162"
echo
echo "To update the container configuration:"
echo "1. Create a new configuration file with:"
echo "   createUser -e 0xFOUND_ENGINE_ID NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata"
echo "2. Apply it with:"
echo "   cat your-config.conf | docker exec -i fluentd-snmp-trap tee /etc/snmp/snmptrapd.conf"
echo "3. Restart the container:"
echo "   docker-compose restart fluentd-snmp" 