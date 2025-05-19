#!/bin/bash
# Fix by mounting new snmptrapd.conf with correct Engine ID

echo "=== Fixing SNMP Trap Configuration with Volume Mount ==="

# Define the correct Engine ID
ENGINE_ID="0x80001F88807C0F9A615F4B0768000000"
echo "Using Engine ID: $ENGINE_ID"

# Stop any running fluentd-snmp-trap container
echo "1. Stopping any running container..."
docker stop fluentd-snmp-trap || true
docker rm fluentd-snmp-trap || true

# Save original docker-compose.yml
echo "2. Saving original docker-compose.yml..."
cp docker-compose.yml docker-compose.yml.bak

# Create fixed SNMPv3 configuration 
echo "3. Creating fixed SNMP configuration..."
mkdir -p fixed-conf/net-snmp fixed-conf/snmp

# Create SNMPv3 user file with Engine ID
cat > fixed-conf/net-snmp/snmptrapd.conf << EOF
createUser -e $ENGINE_ID NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
EOF
chmod 600 fixed-conf/net-snmp/snmptrapd.conf

# Create snmptrapd config with Engine ID
cat > fixed-conf/snmp/snmptrapd.conf << EOF
# SNMPv3 configuration with fixed Engine ID
createUser -e $ENGINE_ID NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
authUser log,execute,net NCEadmin authPriv

# Accept SNMPv1/v2c traps with community string
authCommunity log,execute,net public

# Disable authorization to accept all traps
disableAuthorization yes

# Use formatter script for all incoming traps
traphandle default /usr/local/bin/format-trap.sh
EOF
chmod 644 fixed-conf/snmp/snmptrapd.conf

# Create a temporary docker-compose file with volume mounts
echo "4. Creating docker-compose-fixed.yml..."
cat > docker-compose-fixed.yml << EOF
version: '3'
services:
  fluentd-snmp:
    build: ./fluentd-snmp
    container_name: fluentd-snmp-trap
    ports:
      - "1162:1162/udp"
    volumes:
      - ./fluentd-snmp/conf:/fluentd/etc:ro
      - ./fluentd-snmp/plugins:/fluentd/plugins
      - ./fluentd-snmp/mibs:/fluentd/mibs:ro
      - ./fixed-conf/net-snmp/snmptrapd.conf:/var/lib/net-snmp/snmptrapd.conf
      - ./fixed-conf/snmp/snmptrapd.conf:/etc/snmp/snmptrapd.conf
    environment:
      - SNMPV3_USER=NCEadmin
      - SNMPV3_AUTH_PASS=P@ssw0rdauth
      - SNMPV3_PRIV_PASS=P@ssw0rddata
      - SNMPV3_AUTH_PROTOCOL=SHA
      - SNMPV3_PRIV_PROTOCOL=AES
      - SNMPV3_ENGINE_ID=$ENGINE_ID
      - KAFKA_BROKER=kafka:9092
      - KAFKA_TOPIC=snmp_traps
    restart: always
    networks:
      - opensearch-net

networks:
  opensearch-net:
    external: true
    name: mvp-setup_opensearch-net
EOF

# Start the container with the fixed configuration
echo "5. Starting container with fixed configuration..."
docker-compose -f docker-compose-fixed.yml up -d

# Wait for container to start
echo "6. Waiting for container to start..."
sleep 10

# Verify the container is running
echo "7. Verifying container is running..."
docker ps | grep fluentd-snmp-trap

# Test trap reception if container is running
if docker ps | grep -q fluentd-snmp-trap; then
  echo "8. Testing SNMPv3 trap reception..."
  TEST_ID="VOLUME-FIXED-$(date +%s)"
  docker exec fluentd-snmp-trap snmptrap -v 3 \
    -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth \
    -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' \
    1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID"

  # Wait for processing
  sleep 3

  # Check if trap was received
  echo "9. Checking if trap was received..."
  if docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep -q "$TEST_ID"; then
    echo "✅ SUCCESS: SNMPv3 trap was received!"
    echo "Log entry:"
    docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID"
  else
    echo "❌ FAIL: SNMPv3 trap was not received."
    echo "Last log entries:"
    docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5
  fi
else
  echo "❌ FAIL: Container is not running."
  docker logs fluentd-snmp-trap
fi

echo
echo "=== Fix with volume mount completed ==="
echo "To send SNMPv3 traps to this container, use:"
echo "snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata -l authPriv localhost:1162 ..." 