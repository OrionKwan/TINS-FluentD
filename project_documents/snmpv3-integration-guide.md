# SNMPv3 Integration Guide for System Integrators

This guide explains how to configure and test SNMPv3 trap forwarding from an NM server to the fluentd-snmp container, which then forwards to UDP and Kafka endpoints.

## System Overview

```
[NM Server] --SNMPv3 Traps--> [fluentd-snmp Container] --Forwards to--> [UDP Endpoint]
                                         |
                                         +--------Forwards to--> [Kafka Topic]
```

## Configuration Requirements

### 1. Container Engine ID Discovery

The fluentd-snmp container generates its own Engine ID that must be discovered and used by the NM server sending the traps:

1. Run the Engine ID discovery script on the server hosting the container:
   ```bash
   ./snmpv3-engine-fix.sh
   ```

2. Note the Engine ID output (typically in format `0x80...`):
   ```
   ========== IMPORTANT INFORMATION ==========
   Engine ID: 0x80001F88807C0F9A615F4B0768000000
   =========================================
   ```

### 2. Container Configuration

The container must be properly configured to accept SNMPv3 traps:

1. Ensure the container has the following configuration files:

   a. `/etc/snmp/snmptrapd.conf`:
   ```
   createUser -e 0x[ENGINE_ID] NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
   authUser log,execute,net -e 0x[ENGINE_ID] NCEadmin authPriv
   authUser log,execute,net NCEadmin authPriv
   authCommunity log,execute,net public
   disableAuthorization yes
   traphandle default /usr/local/bin/format-trap.sh
   ```

   b. `/var/lib/net-snmp/snmptrapd.conf`:
   ```
   createUser -e 0x[ENGINE_ID] NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
   ```

2. Verify permission settings:
   ```bash
   mkdir -p /var/lib/snmp /var/lib/net-snmp
   chmod -R 755 /var/lib/snmp /var/lib/net-snmp
   chmod 600 /var/lib/net-snmp/snmptrapd.conf
   ```

3. Ensure the snmptrapd service is running and listening on port 1162:
   ```bash
   snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf 0.0.0.0:1162
   ```

### 3. NM Server Configuration

The NM server must be configured to send traps with the correct Engine ID:

1. Configure the SNMP trap sender with these parameters:
   - SNMPv3 Protocol
   - User: NCEadmin
   - Authentication: MD5, passphrase: P@ssw0rdauth
   - Privacy: AES, passphrase: P@ssw0rddata
   - Engine ID: [DISCOVERED_ENGINE_ID]
   - Target: [CONTAINER_IP]:1162

2. Examples for different NM servers:

   a. **HP OpenView/NNMi**:
   ```
   snmpnotify.conf:
   engineID [DISCOVERED_ENGINE_ID]
   userProfile NCEadmin auth=MD5 priv=AES authPassphrase=P@ssw0rdauth privPassphrase=P@ssw0rddata
   ```

   b. **IBM Tivoli**:
   ```
   /etc/snmp/snmptrap.conf:
   EngineID [DISCOVERED_ENGINE_ID]
   User NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
   ```

   c. **CA Spectrum**:
   ```xml
   <SNMPv3Configuration>
     <engineID>[DISCOVERED_ENGINE_ID]</engineID>
     <securityName>NCEadmin</securityName>
     <authProtocol>MD5</authProtocol>
     <authPassword>P@ssw0rdauth</authPassword>
     <privProtocol>AES</privProtocol>
     <privPassword>P@ssw0rddata</privPassword>
   </SNMPv3Configuration>
   ```

## Testing Procedure

### 1. Basic Trap Testing

Test that the container can receive traps from the command line before testing from the NM server:

```bash
./test-with-correct-engine-id.sh
```

Expected output:
```
✅ SUCCESS: SNMPv3 trap with correct Engine ID was received!
```

### 2. NM Server Testing

1. Create a test trap from your NM server according to your platform's procedures.

2. Verify trap reception in the container:
```bash
docker exec fluentd-snmp-trap tail -f /var/log/snmptrapd.log
```

3. Check UDP forwarding:
```bash
# On the UDP receiving server (165.202.6.129)
tcpdump -i any -n port 1237
```

4. Check Kafka topic messages:
```bash
# Using kafka-console-consumer
kafka-console-consumer --bootstrap-server [KAFKA_SERVER]:9092 --topic [TOPIC_NAME] --from-beginning
```

## Troubleshooting

### Common Issues and Solutions

1. **Authentication Failure**:
   - Verify Engine ID matches exactly (including 0x prefix)
   - Check username, passwords, and auth/priv protocols match

2. **No Traps Received**:
   - Check container is listening on port 1162
   - Verify network connectivity between NM server and container
   - Check firewall rules allow UDP port 1162

3. **Container Receives Traps but No Forwarding**:
   - Check traphandle script (/usr/local/bin/format-trap.sh)
   - Verify connectivity to both UDP endpoint and Kafka broker
   - Check Kafka topic exists and has correct permissions

### Diagnostic Commands

1. Check if snmptrapd is running:
```bash
docker exec fluentd-snmp-trap ps aux | grep snmptrapd
```

2. Debug container's SNMP configuration:
```bash
docker exec fluentd-snmp-trap snmptrapd -Dusm,snmp -f -Lo
```

3. Test trap with debugging:
```bash
snmptrap -v 3 -e [ENGINE_ID] -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata -l authPriv -d [CONTAINER_IP]:1162 '' 1.3.6.1.6.3.1.1.5.1
```

## Appendix: Quick Reference Scripts

### Engine ID Discovery Script

```bash
#!/bin/bash
# Quick script to discover container's Engine ID

# Start snmptrapd in debug mode
docker exec -it fluentd-snmp-trap bash -c "snmptrapd -Dusm,snmp -f -Lo -c /etc/snmp/snmptrapd.conf 0.0.0.0:1162 > /var/log/snmptrapd-debug.log 2>&1 &"
sleep 2

# Send test trap
docker exec -it fluentd-snmp-trap bash -c "snmptrap -v 3 -u NCEadmin -l noAuthNoPriv localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s 'Engine-ID-Discovery'"
sleep 1

# Kill debug process and extract Engine ID
docker exec -it fluentd-snmp-trap bash -c "pkill -f snmptrapd"
sleep 1
docker exec -it fluentd-snmp-trap bash -c "grep 'engineID' /var/log/snmptrapd-debug.log | grep -o '80[0-9A-F: ]*' | head -1 | tr -d ' :'"

# Restart normal snmptrapd
docker exec -it fluentd-snmp-trap bash -c "snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf 0.0.0.0:1162 &"
```

### Quick End-to-End Test Script

```bash
#!/bin/bash
# Quick end-to-end test for SNMPv3 trap forwarding

# Set variables
ENGINE_ID="0x80001F88807C0F9A615F4B0768000000"  # Replace with discovered Engine ID
CONTAINER_IP="192.168.1.100"                    # Replace with your container IP
UDP_TARGET="165.202.6.129"                      # Replace with your UDP target
UDP_PORT="1237"                                 # Replace with your UDP port
TEST_ID="NM-SERVER-TEST-$(date +%s)"

# Send test trap
snmptrap -v 3 -e $ENGINE_ID -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv $CONTAINER_IP:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "$TEST_ID"

echo "Trap sent. Waiting for processing..."
sleep 2

# Check container logs
echo "Checking container logs..."
docker exec fluentd-snmp-trap grep "$TEST_ID" /var/log/snmptrapd.log

# Send direct UDP message to compare
echo "Sending direct UDP message for comparison..."
echo "<snmp_trap><timestamp>$(date)</timestamp><version>SNMPv3</version><user>NCEadmin</user><engineID>$ENGINE_ID</engineID><id>$TEST_ID-DIRECT</id></snmp_trap>" | nc -u $UDP_TARGET $UDP_PORT
``` 