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