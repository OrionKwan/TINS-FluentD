# Deployment Guide for Fixed Fluentd SNMP UDP Forwarding

This guide provides the steps to deploy the fixed Fluentd SNMP trap receiver with properly configured UDP forwarding.

## Overview

The fix addresses the UDP forwarding issue by:
1. Removing `%{time}` from the message format to avoid timekey configuration requirements
2. Creating a Docker image with the fixed configuration baked in, avoiding the read-only volume issue
3. Providing proper buffer configuration for reliable message delivery

## Pre-Deployment Steps

1. **Stop existing container**
   ```bash
   docker stop fluentd-snmp-trap
   ```

2. **Backup any important data or configurations**
   ```bash
   docker cp fluentd-snmp-trap:/var/log/snmptrapd.log ./snmptrapd.log.backup
   ```

## Deployment Steps

1. **Build the fixed Docker image**
   ```bash
   docker build -t fluentd-snmp-fixed -f Dockerfile.fixed .
   ```

2. **Run the fixed container**

   Option 1: Using Docker run command:
   ```bash
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
     --network opensearch-net \
     fluentd-snmp-fixed
   ```

   Option 2: Using Docker Compose:
   ```bash
   # Start with the fixed docker-compose.yml file
   docker-compose -f docker-compose.yml.fixed up -d fluentd-snmp-fixed
   ```

3. **Verify container is running**
   ```bash
   docker ps | grep fluentd-snmp-trap
   ```

4. **Check logs for errors**
   ```bash
   docker logs fluentd-snmp-trap
   ```

## Testing

1. **Send test SNMP trap**
   ```bash
   # Using the existing test script
   ./test-with-engine-id.sh
   ```

2. **Verify UDP forwarding**
   - Check the packet capture on the receiving end for properly formatted messages
   - The format will be: `<snmp_trap><version>SNMPv3</version><data>[SNMP trap data]</data></snmp_trap>`

## Troubleshooting

If issues persist, use the diagnostic script to test direct UDP connectivity:
```bash
./test-udp-direct.sh
```

## Maintenance

If you need to modify the message format in the future:

1. Edit the `fluent.conf.fixed` file
2. Rebuild the Docker image:
   ```bash
   docker build -t fluentd-snmp-fixed -f Dockerfile.fixed .
   ```
3. Restart the container:
   ```bash
   docker stop fluentd-snmp-trap
   docker rm fluentd-snmp-trap
   # Then run the container again with the command from Deployment Steps
   ```

## Verification

Once deployed, you should see SNMP trap messages being properly forwarded to the UDP destination without using the direct UDP scripting approach. This is a permanent solution that fixes the core issue in the Fluentd configuration. 