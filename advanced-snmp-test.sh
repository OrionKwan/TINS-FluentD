#!/bin/bash
# Advanced SNMPv3 test script to help diagnose monitoring issues

TARGET="localhost:1162"

echo "=== Advanced SNMP Test Tool ==="

# Function to run a command with timeout and capture output
run_with_timeout() {
    local cmd="$1"
    local desc="$2"
    local timeout_seconds=5
    local output
    
    echo "⏳ Testing: $desc"
    echo "  Command: $cmd"
    
    # Execute command with timeout
    output=$(timeout $timeout_seconds bash -c "$cmd" 2>&1)
    local status=$?
    
    if [ $status -eq 124 ]; then
        echo "⚠️ Test timed out after $timeout_seconds seconds"
    elif [ $status -ne 0 ]; then
        echo "❌ Test failed with status $status"
        echo "  Error: $output"
    else
        echo "✓ Test completed"
        echo "  Output: ${output:0:100}${output:100:+...}"
    fi
    echo "---"
}

# 1. Test basic connectivity (SNMPv2c)
echo "1️⃣ Testing basic SNMP connectivity (SNMPv2c)"
run_with_timeout "snmptrap -v 2c -c public $TARGET '' 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s \"BASIC-TEST-$(date +%s)\"" "SNMPv2c with community 'public'"

# 2. Test standard SNMPv3 format
echo "2️⃣ Testing SNMPv3 with authentication"
run_with_timeout "snmptrap -v 3 -u NCEadmin -a MD5 -A P@ssw0rdauth -l authNoPriv $TARGET '' 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s \"AUTHNOPRIV-TEST-$(date +%s)\"" "SNMPv3 with auth but no privacy"

# 3. Test SNMPv3 with auth+priv
echo "3️⃣ Testing SNMPv3 with authentication and privacy"
run_with_timeout "snmptrap -v 3 -u NCEadmin -a MD5 -A P@ssw0rdauth -x DES -X P@ssw0rddata -l authPriv $TARGET '' 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s \"AUTHPRIV-TEST-$(date +%s)\"" "SNMPv3 with auth and privacy"

# 4. Test with explicit Engine ID
echo "4️⃣ Testing SNMPv3 with explicit Engine ID"
run_with_timeout "snmptrap -v 3 -e 0x8000000001020304 -u NCEadmin -a MD5 -A P@ssw0rdauth -x DES -X P@ssw0rddata -l authPriv $TARGET '' 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s \"ENGINEID-TEST-$(date +%s)\"" "SNMPv3 with explicit Engine ID"

# 5. Test with Engine ID discovery enabled
echo "5️⃣ Testing SNMPv3 with Engine ID discovery"
run_with_timeout "snmpget -v 3 -u NCEadmin -a MD5 -A P@ssw0rdauth -l authNoPriv -On localhost:161 SNMPv2-MIB::sysDescr.0 2>&1 | grep -i 'engine'" "Probe for Engine ID on localhost:161"

# 6. Test port availability
echo "6️⃣ Testing port availability"
run_with_timeout "nc -v -z -u localhost 1162" "Check if port 1162/udp is open"

# 7. Send a raw UDP packet
echo "7️⃣ Sending raw UDP packet to port 1162"
echo -e "RAWPACKET-TEST-$(date +%s)" > /tmp/rawpacket
run_with_timeout "cat /tmp/rawpacket | nc -u localhost 1162" "Send raw UDP data to port 1162"
rm -f /tmp/rawpacket

echo "Advanced tests complete."
echo "If the enhanced monitor script isn't showing engine IDs, check:"
echo "1. If the port is already in use by another process"
echo "2. If the monitor script has sufficient permissions"
echo "3. If there are any firewall rules blocking UDP traffic"
echo "4. If the tcpdump capture shows valid SNMPv3 packets with engine IDs" 