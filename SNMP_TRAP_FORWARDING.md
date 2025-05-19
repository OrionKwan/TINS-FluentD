# SNMP Trap Forwarding Configuration

## Quick Reference Guide

This document explains how SNMP traps are forwarded from the host machine to the Docker container.

## Current Network Setup

```
SNMP Device (172.29.36.80) → Firewall (192.168.8.3) → Docker Host (192.168.8.30) → Container (192.168.8.100)
```

## Forwarding Rules

The host machine (192.168.8.30) is configured to forward all SNMP trap traffic (UDP port 1162) to the Docker container (192.168.8.100) using these IP tables rules:

```bash
# Forward SNMP trap traffic with interface specificity
iptables -t nat -I PREROUTING 1 -i ens160 -p udp --dport 1162 -j DNAT --to-destination 192.168.8.100:1162

# Enable masquerading
iptables -t nat -A POSTROUTING -o ens160 -j MASQUERADE
```

Additionally, we prevent conflicts with Docker's auto-created NAT rules by removing them:

```bash
# Remove potential conflicting Docker NAT rules
iptables -t nat -D DOCKER -p udp --dport 1162 -j DNAT --to-destination 172.18.0.3:1162
```

## SNMP Trap Daemon Configuration

The snmptrapd daemon inside the container is explicitly configured to listen on the macvlan interface (192.168.8.100):

```bash
snmptrapd -Lf /var/log/snmptrapd.log -c /fluentd/etc/snmptrapd.conf -f -Lo -A -n 192.168.8.100 1162
```

This ensures that SNMP traps are received on the external IP address rather than the internal Docker network.

## Checking Current Status

To check if forwarding is properly configured:

```bash
# Check if IP forwarding is enabled
cat /proc/sys/net/ipv4/ip_forward
# Should return '1'

# Check existing forwarding rules
sudo iptables -t nat -L -n | grep 1162
```

## Applying Forwarding Rules

If the rules need to be reapplied:

```bash
sudo /home/nmc/mvp-setup/iptables-rules.sh
```

To reconfigure the SNMP trap daemon:

```bash
sudo /home/nmc/mvp-setup/configure-snmptrapd.sh
```

## Container Network Configuration

The fluentd-snmp-trap container is connected to two networks:

1. **opensearch-net** (172.18.0.0/16) - For internal communication with Kafka
2. **snmpmacvlan** (192.168.8.0/24) - For external SNMP trap reception

Check container IP addresses:

```bash
docker inspect fluentd-snmp-trap -f '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}: {{$conf.IPAddress}}{{printf "\n"}}{{end}}'
```

## Troubleshooting

If SNMP traps aren't being received:

1. Verify that iptables rules are active
2. Check that the container is running and snmptrapd is listening on 192.168.8.100
3. Ensure IP forwarding is enabled on the host 
4. Check Docker logs for authentication errors (for SNMPv3 traps)
5. Run tcpdump to verify traffic flow:
   ```bash
   docker exec fluentd-snmp-trap tcpdump -i eth1 -n udp port 1162
   ```

For detailed network architecture and configuration, see [NETWORK_SETUP_GUIDE.md](./NETWORK_SETUP_GUIDE.md). 