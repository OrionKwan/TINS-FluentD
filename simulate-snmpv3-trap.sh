#!/bin/bash
# Script to simulate a source device sending an SNMPv3 trap with the IP-based Engine ID

# Set up the expected Engine ID
IP="172.29.36.80"
IP_HEX=$(printf '%02X%02X%02X%02X' $(echo $IP | tr '.' ' '))
ENGINE_ID="0x80000000c001${IP_HEX}"  # Standard prefix + IP in hex

echo "===== Simulating SNMPv3 Trap from Source Device ====="
echo "Using Engine ID: $ENGINE_ID (based on IP: $IP)"

# 1. Make sure the container with our IP-based Engine ID is running
if ! docker ps | grep -q fluentd-snmp-trap-ip; then
  echo "Container fluentd-snmp-trap-ip is not running. Running setup script..."
  ./update-production-engine-id.sh
  sleep 5
fi

# Get container IP and port
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' fluentd-snmp-trap-ip)
echo "Target container IP address: $CONTAINER_IP"

# 2. Send a test trap from simulated device
echo "Sending test trap as if from a device with Engine ID: $ENGINE_ID"
TRAP_ID="SIMULATED-DEVICE-$(date +%s)"

snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a SHA -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv $CONTAINER_IP:1162 '' \
  1.3.6.1.4.1.2011.2.15.1.7.1.0.1 \
  1.3.6.1.4.1.2011.2.15.1.7.1.1.1 s "TestNE-$TRAP_ID" \
  1.3.6.1.4.1.2011.2.15.1.7.1.1.2 s "Huawei-Router" 2>/dev/null

echo "Trap sent. Waiting for processing..."
sleep 3

# 3. Check if the trap was received
echo "Checking if the trap was received..."
if docker logs fluentd-snmp-trap-ip | grep -q "$TRAP_ID"; then
  echo "✅ SUCCESS: Trap was received successfully!"
  docker logs fluentd-snmp-trap-ip | grep "$TRAP_ID"
  
  # Check for MIB translation
  if docker logs fluentd-snmp-trap-ip | grep -q "hwNmNorthboundNEName"; then
    echo "✅ SUCCESS: MIB names are being properly translated!"
    docker logs fluentd-snmp-trap-ip | grep "hwNmNorthboundNEName"
  else
    echo "⚠️ WARNING: MIB names are not being translated. Raw OIDs appear in the logs."
  fi
else
  echo "❌ FAIL: Trap was not found in container logs."
  echo "Recent container logs:"
  docker logs fluentd-snmp-trap-ip --tail 20
fi

# 4. Show how to check inside the container
echo -e "\nTo manually check trap reception inside container, run:"
echo "docker exec -it fluentd-snmp-trap-ip cat /var/log/snmptrapd.log | grep '$TRAP_ID'"

echo -e "\n===== Simulation Complete ====="
echo "This test simulated a network device sending a trap with Engine ID: $ENGINE_ID"
echo "If the trap was received, the Engine ID configuration is working correctly." 