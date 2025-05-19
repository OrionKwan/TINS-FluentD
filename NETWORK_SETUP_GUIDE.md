# Network Setup Guide for SNMP Trap Reception System

## Overview

This document provides an operational guide for the network setup of our SNMP trap reception system, explaining how SNMP traps are routed from external devices to our Docker-based processing infrastructure.

## Network Architecture

The system uses a combination of physical networking, Docker networking, and IP forwarding to ensure SNMP traps are properly received and processed.

### Network Diagram

```
                                                   ┌────────────────────────────────────────────────────────┐
                                                   │                 Docker Host Machine                     │
                                                   │                (192.168.8.30/24)                        │
                                                   │                                                         │
                                                   │   ┌─────────────┐     ┌─────────────────────────────┐  │
┌──────────────┐   ┌───────────────┐   Layer 2     │   │  IP Tables  │     │   Docker Container          │  │
│  SNMP Device │   │   Firewall    │  Connection   │   │  Forwarding │     │                             │  │
│(172.29.36.80)│──▶│  with VDOM    │───────────────┼──▶│  UDP:1162   │────▶│ fluentd-snmp (192.168.8.100)│  │
└──────────────┘   │(192.168.8.3)  │               │   │             │     │                             │  │
                   └───────────────┘               │   └─────────────┘     └─────────────────────────────┘  │
                                                   │                                       │                 │
                                                   └───────────────────────────────────────┼─────────────────┘
                                                                                           │
                                                                                           │
                                                                                           ▼
                                                                         ┌─────────────────────────────┐
                                                                         │      Kafka, OpenSearch      │
                                                                         │      and other services     │
                                                                         └─────────────────────────────┘
```

### Network Components

1. **SNMP Device (172.29.36.80)**
   - Source of SNMP trap messages
   - Configured to send SNMPv3 traps to the Firewall

2. **Firewall with VDOM (192.168.8.3)**
   - Acts as a gateway between the device network (172.29.x.x) and our local network (192.168.8.x)
   - VDOM has been specifically configured to allow SNMP traffic to 192.168.8.30

3. **Docker Host (192.168.8.30)**
   - Physical server running Docker
   - Forwards SNMP trap traffic to the container using iptables rules
   - Acts as a bridge between the physical and virtual networks

4. **Docker Container (192.168.8.100)**
   - Runs fluentd-snmp-trap service
   - Has direct network connectivity via macvlan
   - Processes SNMP traps and forwards to Kafka

5. **Backend Services**
   - Kafka, OpenSearch, and other components that process and store the SNMP trap data

## Network Implementation Details

### Docker Networking Configuration

The setup uses two Docker networks:

1. **Docker Bridge Network (opensearch-net)**
   - Internal network with subnet 172.18.0.0/16
   - Used for container-to-container communication
   - Connects fluentd-snmp-trap to Kafka, OpenSearch, etc.

2. **Docker Macvlan Network (snmpmacvlan)**
   - External network with subnet 192.168.8.0/24 (same as host network)
   - Provides a dedicated IP (192.168.8.100) for the fluentd-snmp-trap container
   - Created with this command:
     ```
     docker network create -d macvlan --subnet=192.168.8.0/24 --gateway=192.168.8.1 -o parent=ens160 snmpmacvlan
     ```

### Traffic Flow for SNMP Traps

1. SNMP device (172.29.36.80) sends traps to the firewall
2. Firewall forwards these traps to the Docker host (192.168.8.30) on UDP port 1162
3. Docker host's iptables rules forward the traffic to the container (192.168.8.100)
4. The container processes the traps and forwards them to Kafka
5. Other services consume and process the data from Kafka

### IP Tables Configuration

The Docker host uses these iptables rules for forwarding:

```bash
# Forward SNMP trap traffic from host to container with interface specificity
iptables -t nat -I PREROUTING 1 -i ens160 -p udp --dport 1162 -j DNAT --to-destination 192.168.8.100:1162

# Remove conflicting Docker rules
iptables -t nat -D DOCKER -p udp --dport 1162 -j DNAT --to-destination 172.18.0.3:1162

# Enable masquerading for forwarded packets
iptables -t nat -A POSTROUTING -o ens160 -j MASQUERADE
```

These rules ensure that:
1. Incoming SNMP trap traffic on ens160 is redirected to the container's macvlan IP (192.168.8.100)
2. Any conflicting Docker NAT rules are removed to prevent redirection to the internal Docker IP (172.18.0.3)
3. Return traffic is properly masqueraded

These rules are applied at system startup via the `iptables-rules.sh` script, which is configured to run at boot time.

### SNMP Trap Daemon Configuration

The fluentd-snmp-trap container runs a snmptrapd daemon that is explicitly configured to listen on the macvlan interface (192.168.8.100):

```bash
snmptrapd -Lf /var/log/snmptrapd.log -c /fluentd/etc/snmptrapd.conf -f -Lo -A -n 192.168.8.100 1162
```

This configuration is applied by the `configure-snmptrapd.sh` script after container startup.

## SNMPv3 Authentication Configuration

The fluentd-snmp-trap container is configured to handle SNMPv3 authentication with these parameters:

- **Username**: NCEadmin
- **Authentication Protocol**: SHA
- **Authentication Password**: P@ssw0rdauth
- **Privacy Protocol**: AES
- **Privacy Password**: P@ssw0rddata
- **Engine ID**: Dynamically detected or configured from the incoming trap

## Maintenance and Troubleshooting

### Verifying Connectivity

1. **Check if the container is running and has the correct IP:**
   ```
   docker inspect fluentd-snmp-trap -f '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}: {{$conf.IPAddress}}{{printf "\n"}}{{end}}'
   ```

2. **Verify iptables forwarding rules:**
   ```
   sudo iptables -t nat -L -n
   ```

3. **Check if IP forwarding is enabled:**
   ```
   cat /proc/sys/net/ipv4/ip_forward
   ```

### Common Issues and Solutions

1. **SNMP traps not reaching the container:**
   - Verify firewall settings allowing UDP 1162 traffic
   - Check iptables rules on the Docker host
   - Ensure IP forwarding is enabled on the host

2. **SNMPv3 authentication failures:**
   - Verify the credentials match between the sending device and the container
   - Check the Engine ID configuration
   - Examine the container logs for authentication errors

3. **Container not receiving traffic on 192.168.8.100:**
   - Check that the macvlan network is properly configured
   - Ensure the container has the correct IP assigned
   - Verify no IP address conflicts in the network

### Re-applying Network Configuration

If the server restarts or rules are lost, run:

```bash
sudo /home/nmc/mvp-setup/iptables-rules.sh
sudo /home/nmc/mvp-setup/configure-snmptrapd.sh
```

## Security Considerations

1. **Firewall Configuration:** The existing firewall with VDOM provides network segmentation and security between the 172.29.x.x and 192.168.8.x networks.

2. **SNMPv3 Security:** The system uses SNMPv3 with authentication and privacy, providing secure transmission of SNMP traps.

3. **Network Isolation:** The Docker macvlan network is used to provide a dedicated IP for the SNMP trap receiver while maintaining network isolation.

## Appendix: Configuration Files

### iptables-rules.sh

```bash
#!/bin/bash

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1

# Remove any existing rules
iptables -t nat -D PREROUTING -p udp --dport 1162 -j DNAT --to-destination 192.168.8.100:1162 2>/dev/null || true
iptables -t nat -D DOCKER -p udp --dport 1162 -j DNAT --to-destination 172.18.0.3:1162 2>/dev/null || true

# Forward SNMP trap traffic from host to container with higher specificity
iptables -t nat -I PREROUTING 1 -i ens160 -p udp --dport 1162 -j DNAT --to-destination 192.168.8.100:1162

# Enable masquerading for forwarded packets
iptables -t nat -A POSTROUTING -o ens160 -j MASQUERADE

echo "SNMP trap forwarding rules applied successfully"
```

### configure-snmptrapd.sh

```bash
#!/bin/bash

# Script to configure snmptrapd to listen on the macvlan interface
CONTAINER_NAME="fluentd-snmp-trap"

echo "Configuring snmptrapd in $CONTAINER_NAME container..."

# Give the container time to start
sleep 5

# Get the current container status
CONTAINER_RUNNING=$(docker ps -q -f name=$CONTAINER_NAME)

if [ -z "$CONTAINER_RUNNING" ]; then
  echo "Container $CONTAINER_NAME is not running!"
  exit 1
fi

echo "Restarting snmptrapd to listen on 192.168.8.100:1162..."

# Restart snmptrapd to listen on the macvlan interface
docker exec $CONTAINER_NAME sh -c "pkill snmptrapd && \
  snmptrapd -Lf /var/log/snmptrapd.log -c /fluentd/etc/snmptrapd.conf -f -Lo -A -n 192.168.8.100 1162 &"

# Check if the daemon is running correctly
SNMPTRAPD_COUNT=$(docker exec $CONTAINER_NAME sh -c "ps aux | grep -v grep | grep '192.168.8.100 1162' | wc -l")

if [ "$SNMPTRAPD_COUNT" -gt 0 ]; then
  echo "snmptrapd is now listening on 192.168.8.100:1162"
  exit 0
else
  echo "Failed to configure snmptrapd!"
  exit 1
fi
```

### Docker Compose Network Configuration

```yaml
fluentd-snmp:
  build:
    context: ./fluentd-snmp
    dockerfile: Dockerfile
  container_name: fluentd-snmp-trap
  ports:
    - "1162:1162/udp"
  volumes:
    - ./fluentd-snmp/mibs:/fluentd/mibs:ro
    - ./fluentd-snmp/conf:/fluentd/etc:ro
  environment:
    - SNMPV3_USER=NCEadmin
    - SNMPV3_AUTH_PASS=P@ssw0rdauth
    - SNMPV3_PRIV_PASS=P@ssw0rddata
    - SNMPV3_AUTH_PROTOCOL=SHA
    - SNMPV3_PRIV_PROTOCOL=AES
    - KAFKA_BROKER=kafka:9092
    - KAFKA_TOPIC=snmp_traps
  networks:
    opensearch-net: {}  # For Kafka/internal communication
    snmpmacvlan:        # For SNMP trap reception
      ipv4_address: 192.168.8.100

networks:
  opensearch-net:
    driver: bridge
  snmpmacvlan:
    external: true  # Pre-created macvlan network
``` 