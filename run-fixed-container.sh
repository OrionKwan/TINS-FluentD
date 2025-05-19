#!/bin/bash

# Stop and remove existing container if it exists
docker stop fluentd-snmp-trap 2>/dev/null || true
docker rm fluentd-snmp-trap 2>/dev/null || true

# Install the UDP plugin
docker run --name tmp-fluentd fluent/fluentd:v1.16-1 gem install fluent-plugin-udp
docker commit tmp-fluentd fluentd-with-udp
docker rm tmp-fluentd

# Start the container with the fixed configuration
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
    -e UDP_FORWARD_HOST=165.202.6.129 \
    -e UDP_FORWARD_PORT=1237 \
    --network mvp-setup_opensearch-net \
    -v $(pwd)/fluent.conf.fixed:/fluentd/etc/fluent.conf \
    -v $(pwd)/fluentd-snmp/plugins:/fluentd/plugins \
    -v $(pwd)/fluentd-snmp/conf/snmptrapd.conf:/etc/snmp/snmptrapd.conf \
    fluentd-with-udp

echo "Container started. Check logs with: docker logs fluentd-snmp-trap" 