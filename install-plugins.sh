#!/bin/bash
# Script to install necessary Fluentd plugins for parallel UDP and Kafka output

echo "=== Installing Fluentd Plugins for Parallel Output ==="

# Stop the current container
echo "1. Stopping the container..."
docker stop fluentd-snmp-trap || true

# Create directories for buffer files
echo "2. Creating buffer directories..."
mkdir -p fluentd-buffer/kafka fluentd-buffer/error fluentd-log

# Install plugins inside the container
echo "3. Creating Dockerfile for plugin installation..."
cat > Dockerfile.plugins << EOF
FROM fluentd-snmp-fixed

# Install additional plugins
USER root
RUN apk add --no-cache build-base ruby-dev && \
    gem install fluent-plugin-kafka -v 0.19.4 && \
    gem install fluent-plugin-udp -v 0.0.5 && \
    apk del build-base ruby-dev && \
    rm -rf /tmp/* /var/tmp/* /usr/lib/ruby/gems/*/cache/*.gem

# Create buffer directories
RUN mkdir -p /fluentd/buffer/kafka /fluentd/buffer/error /fluentd/log && \
    chmod -R 777 /fluentd/buffer /fluentd/log

# Use our custom entrypoint
ENTRYPOINT ["/custom-entrypoint.sh"]

# Command
CMD ["fluentd", "-p", "/fluentd/plugins", "-c", "/fluentd/etc/fluent.conf"]
EOF

# Build the updated image
echo "4. Building updated image with plugins..."
docker build -f Dockerfile.plugins -t fluentd-snmp-fixed-parallel .

# Run the container with volume mounts for buffers
echo "5. Starting container with buffer volumes..."
docker run -d --name fluentd-snmp-trap \
  -p 1162:1162/udp \
  -v $(pwd)/fluentd-snmp/conf:/fluentd/etc:ro \
  -v $(pwd)/fluentd-snmp/plugins:/fluentd/plugins \
  -v $(pwd)/fluentd-snmp/mibs:/fluentd/mibs:ro \
  -v $(pwd)/fluentd-buffer:/fluentd/buffer \
  -v $(pwd)/fluentd-log:/fluentd/log \
  -e KAFKA_BROKER=kafka:9092 \
  -e KAFKA_TOPIC=snmp_traps \
  -e UDP_FORWARD_HOST=165.202.6.129 \
  -e UDP_FORWARD_PORT=1237 \
  -e SNMPV3_ENGINE_ID=0x80001F88807C0F9A615F4B0768000000 \
  --network mvp-setup_opensearch-net \
  fluentd-snmp-fixed-parallel

# Wait for container to start
echo "6. Waiting for container to start..."
sleep 10

# Check container status
echo "7. Checking container status..."
if docker ps | grep -q fluentd-snmp-trap; then
  echo "Container is running"
  docker logs fluentd-snmp-trap | tail -n 20
else
  echo "Container failed to start"
  docker logs fluentd-snmp-trap
  exit 1
fi

echo
echo "=== Plugin Installation Completed ==="
echo "The fluentd-snmp-trap container is now configured for parallel UDP and Kafka output."
echo "To test, send an SNMP trap with:"
echo "snmptrap -v 3 -e 0x80001F88807C0F9A615F4B0768000000 -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata -l authPriv localhost:1162 ..." 