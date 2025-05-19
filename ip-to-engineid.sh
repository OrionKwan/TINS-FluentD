#!/bin/bash
# Convert IP address to SNMPv3 Engine ID formats

# Check if an IP was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <ip-address>"
    echo "Example: $0 172.29.36.80"
    exit 1
fi

IP="$1"

# Validate IP address format
if ! [[ $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid IP address format. Please use format: xxx.xxx.xxx.xxx"
    exit 1
fi

# Convert IP to hex
ip_hex=""
for octet in $(echo $IP | tr '.' ' '); do
    hex=$(printf "%02X" $octet)
    ip_hex="${ip_hex}${hex}"
done

echo "IP Address: $IP"
echo "IP in hex: $ip_hex"
echo 

# Standard SNMPv3 Engine ID format with IP
# Format: 0x80 + 4-byte enterprise ID + format (01=IPv4) + IP
FORMAT_IPV4_BYTE="01"
echo "SNMPv3 Engine ID formats derived from IP address:"
echo "1. Standard format with default enterprise ID (0x00000000):"
echo "   0x800000000001${ip_hex}"
echo

echo "2. Format with Cisco enterprise ID (0x000000C0):"
echo "   0x800000C00001${ip_hex}"
echo

echo "3. Format with no enterprise indicator (direct):"
echo "   0x80${ip_hex}"
echo

echo "4. Format with RFC 3411 complete compliance:"
echo "   0x80000000${FORMAT_IPV4_BYTE}${ip_hex}"
echo

echo "To use these engine IDs with SNMP commands:"
echo "snmptrap -v 3 -e 0x800000000001${ip_hex} -u username ..."
echo

echo "To detect which format is in use in your environment:"
echo "1. Run one of the monitor scripts and check real packets"
echo "2. Use the extract-engine-id.sh script with sudo"
echo "3. Or use Wireshark to analyze packet details" 