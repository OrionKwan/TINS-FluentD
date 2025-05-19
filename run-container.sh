#!/bin/bash

# Stop and remove existing container if it exists
docker stop fluentd-snmp-trap 2>/dev/null || true
docker rm fluentd-snmp-trap 2>/dev/null || true

# Run the container with our final image
docker run -d --name fluentd-snmp-trap \
  -p 1162:1162/udp \
  -e SNMPV3_USER=NCEadmin \
  -e SNMPV3_AUTH_PASS=P@ssw0rdauth \
  -e SNMPV3_PRIV_PASS=P@ssw0rddata \
  -e SNMPV3_AUTH_PROTOCOL=SHA \
  -e SNMPV3_PRIV_PROTOCOL=AES \
  -e SNMPV3_ENGINE_ID=0x80001F88807C0F9A615F4B0768000000 \
  -e KAFKA_BROKER=kafka:9092 \
  -e KAFKA_TOPIC=snmp_traps \
  --network mvp-setup_opensearch-net \
  fluentd-snmp-final

# Check if container is running
if docker ps | grep -q fluentd-snmp-trap; then
  echo "Container started successfully"
  echo "Logs:"
  docker logs fluentd-snmp-trap | tail -10
else
  echo "Container failed to start. Checking logs:"
  docker logs fluentd-snmp-trap
fi 