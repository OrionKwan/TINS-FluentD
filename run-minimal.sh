#!/bin/bash

# Stop and remove existing container if it exists
docker stop fluentd-snmp-trap 2>/dev/null || true
docker rm fluentd-snmp-trap 2>/dev/null || true

# Build the image
docker build -t fluentd-snmp-minimal -f Dockerfile.minimal .

# Run the container with our minimal image
docker run -d --name fluentd-snmp-trap \
  -p 1162:1162/udp \
  -e KAFKA_BROKER=kafka:9092 \
  -e KAFKA_TOPIC=snmp_traps \
  --network mvp-setup_opensearch-net \
  fluentd-snmp-minimal

# Check if container is running
if docker ps | grep -q fluentd-snmp-trap; then
  echo "Container started successfully"
  echo "Logs:"
  docker logs fluentd-snmp-trap | tail -10
else
  echo "Container failed to start. Checking logs:"
  docker logs fluentd-snmp-trap
fi 