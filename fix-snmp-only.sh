#!/bin/bash
# Script to update only SNMP configuration in the running container

echo "=== Updating SNMP Configuration Only ==="

# Stop the current container
echo "1. Stopping the container..."
docker stop fluentd-snmp-trap

# Define the correct Engine ID
ENGINE_ID="0x80001F88807C0F9A615F4B0768000000"
echo "Using Engine ID: $ENGINE_ID"

# Create configuration files with correct Engine ID
echo "2. Creating configuration files..."

# Create SNMPv3 user file
echo "createUser -e $ENGINE_ID NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata" > snmptrapd-users.conf

# Create snmptrapd config
cat > snmptrapd-fixed.conf << EOF
# SNMPv3 configuration 
createUser -e $ENGINE_ID NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
authUser log,execute,net NCEadmin authPriv

# Accept SNMPv1/v2c traps with community string
authCommunity log,execute,net public

# Disable authorization to accept all traps
disableAuthorization yes

# Use formatter script for all incoming traps
traphandle default /usr/local/bin/format-trap.sh
EOF

# Start container again with environment variable
echo "3. Starting the container with the Engine ID environment variable..."
docker-compose up -d fluentd-snmp

# Wait for container to start
echo "4. Waiting for container to start..."
sleep 10

# Create fix script
echo "5. Creating fix script..."
cat > snmp-fix.sh << 'EOF'
#!/bin/sh
# Create directories if they don't exist
mkdir -p /var/lib/net-snmp /etc/snmp

# Copy config files
cat /tmp/snmptrapd-users.conf > /var/lib/net-snmp/snmptrapd.conf
cat /tmp/snmptrapd-fixed.conf > /etc/snmp/snmptrapd.conf

# Set permissions
chmod 600 /var/lib/net-snmp/snmptrapd.conf
chmod 644 /etc/snmp/snmptrapd.conf

# Kill existing snmptrapd
pkill -f snmptrapd || true
sleep 1

# Start snmptrapd with the new configuration
/usr/sbin/snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf 0.0.0.0:1162 &
sleep 2

# Check if snmptrapd is running
if pgrep snmptrapd > /dev/null; then
  echo "snmptrapd is running with correct Engine ID"
  exit 0
else
  echo "Failed to start snmptrapd"
  exit 1
fi
EOF

# Copy files to container
echo "6. Copying files to container..."
docker cp snmptrapd-users.conf fluentd-snmp-trap:/tmp/
docker cp snmptrapd-fixed.conf fluentd-snmp-trap:/tmp/
docker cp snmp-fix.sh fluentd-snmp-trap:/tmp/
docker exec fluentd-snmp-trap chmod +x /tmp/snmp-fix.sh

# Run fix script inside container
echo "7. Running fix script inside container..."
docker exec fluentd-snmp-trap /tmp/snmp-fix.sh

# Test if SNMPv3 works with the new configuration
echo "8. Testing SNMPv3 configuration..."
TEST_ID="FIXED-$(date +%s)"

# Send a test trap with the Engine ID
echo "Sending test trap with Engine ID: $ENGINE_ID"
docker exec fluentd-snmp-trap snmptrap -v 3 \
  -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID"

sleep 3

# Check if the trap was received
echo "9. Checking if trap was logged..."
if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$TEST_ID"; then
  echo "✅ SUCCESS: SNMPv3 trap was received!"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID"
else
  echo "❌ FAIL: SNMPv3 trap not found in log."
  echo "Last log entries:"
  docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5
fi

echo
echo "=== SNMP Configuration Update Completed ==="
echo "To send SNMPv3 traps to this container, use:"
echo "snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata -l authPriv localhost:1162 ..." 