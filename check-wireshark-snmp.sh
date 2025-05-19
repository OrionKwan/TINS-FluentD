#!/bin/bash
# Script to verify and configure Wireshark for proper SNMPv3 trap display

echo "===== Wireshark SNMP Configuration Helper ====="

# Check if Wireshark is installed
if ! command -v wireshark &>/dev/null; then
    echo "Wireshark is not installed. Please install it first."
    exit 1
fi

# Check Wireshark version
WIRESHARK_VERSION=$(wireshark --version | head -n1 | awk '{print $2}')
echo "Detected Wireshark version: $WIRESHARK_VERSION"

# PCAP file from previous capture
PCAP_FILE="source_ip_172.29.36.80_trap_capture.pcap"
if [ ! -f "$PCAP_FILE" ]; then
    echo "Previous capture file not found: $PCAP_FILE"
    echo "Would you like to run a new capture? (y/n)"
    read -r CAPTURE
    if [[ "$CAPTURE" == "y" || "$CAPTURE" == "Y" ]]; then
        ./capture-source-ip-trap.sh
    else
        echo "Please specify the path to your PCAP file:"
        read -r PCAP_FILE
    fi
fi

# 1. Verify SNMP protocol detection
echo -e "\n===== SNMP Protocol Detection ====="
SNMP_PACKETS=$(tshark -r "$PCAP_FILE" -Y "snmp" -T fields -e frame.number | wc -l)
SNMPV3_PACKETS=$(tshark -r "$PCAP_FILE" -Y "snmp.msgVersion == 3" -T fields -e frame.number | wc -l)

echo "Total SNMP packets detected: $SNMP_PACKETS"
echo "SNMPv3 packets detected: $SNMPV3_PACKETS"

if [ "$SNMPV3_PACKETS" -eq 0 ] && [ "$SNMP_PACKETS" -gt 0 ]; then
    echo "WARNING: Packets are detected as SNMP but not as SNMPv3"
    echo "This suggests Wireshark is detecting the wrong SNMP version"
elif [ "$SNMP_PACKETS" -eq 0 ]; then
    echo "WARNING: No SNMP packets detected at all"
    echo "This suggests port configuration issues or packet capture problems"
fi

# 2. Check SNMP packet details
echo -e "\n===== SNMP Packet Details ====="
PORT_NUMBERS=$(tshark -r "$PCAP_FILE" -T fields -e udp.dstport | sort -u)
echo "UDP destination ports in capture: $PORT_NUMBERS"

# Extract the first SNMP packet for detailed analysis
tshark -r "$PCAP_FILE" -Y "snmp" -w /tmp/first_snmp_packet.pcap -c 1 2>/dev/null

# 3. Configuration guidance
echo -e "\n===== Wireshark Configuration Guide ====="
echo "To properly view SNMPv3 traps in Wireshark:"

echo "1. Open Wireshark and go to Edit → Preferences"
echo "2. Expand 'Protocols' in the left panel"
echo "3. Scroll down and select 'SNMP'"
echo "4. Make sure the following settings are configured:"
echo "   - Check 'Validate packet' is UNCHECKED (can cause decoding issues)"
echo "   - For SNMPv3 decryption, click 'User Table' and add:"
echo "     Username: NCEadmin"
echo "     Authentication: SHA1"
echo "     Password: P@ssw0rdauth"
echo "     Privacy: AES"
echo "     Password: P@ssw0rddata"

echo -e "\n5. For MIB loading:"
echo "   - Go to 'Name Resolution' section"
echo "   - Select 'SNMP' subsection"
echo "   - Check 'Load MIB modules'"
echo "   - Add your MIB path: $(pwd)/fluentd-snmp/mibs"

echo -e "\n6. After adjusting these settings, restart Wireshark"

# 4. For OID translation issues
echo -e "\n===== OID Translation Check ====="
echo "If trap OIDs aren't translating to readable names:"
echo "1. Verify MIB files are in the correct location:"
echo "   - Container path: /usr/share/snmp/mibs/"
echo "   - Local path: $(pwd)/fluentd-snmp/mibs/"

echo "2. Check specific OIDs in your capture:"
TRAP_OIDS=$(tshark -r "$PCAP_FILE" -Y "snmp.trap.generic-trap" -T fields -e snmp.objectID 2>/dev/null)
if [ -n "$TRAP_OIDS" ]; then
    echo "   Detected trap OIDs: $TRAP_OIDS"
else
    echo "   No specific trap OIDs detected in capture"
fi

# 5. Commands to open the capture properly
echo -e "\n===== Commands to Open Capture Properly ====="
echo "Run one of these commands to open your capture:"
echo "1. Basic open:"
echo "   wireshark \"$PCAP_FILE\""
echo "2. With SNMP filter:"
echo "   wireshark -Y \"snmp\" \"$PCAP_FILE\""
echo "3. With SNMPv3 filter:"
echo "   wireshark -Y \"snmp.msgVersion == 3\" \"$PCAP_FILE\""

# 6. Wireshark display filters
echo -e "\n===== Useful Wireshark Display Filters ====="
echo "Once in Wireshark, use these display filters:"
echo "1. Show only SNMP:                snmp"
echo "2. Show only SNMPv3:              snmp.msgVersion == 3"
echo "3. Show authentication details:   snmp.msgAuthenticationParameters"
echo "4. Show SNMP traps:               snmp.trap"
echo "5. Show specific Engine ID:       snmp.msgAuthoritativeEngineID == 80:00:00:00:c0:01:ac:1d:24:50"
echo "6. Show decrypted payload:        snmpdecrypted"

chmod +x "$0" 