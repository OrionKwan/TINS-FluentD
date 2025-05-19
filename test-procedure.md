# Testing Procedure for fluentd-snmp Container

This document outlines the complete procedure for testing the fluentd-snmp container functionality, including SNMP trap reception, processing, and UDP/Kafka forwarding.

## Prerequisites
- Docker and docker-compose installed and running
- Access to the fluentd-snmp container logs
- Network access to the UDP destination (165.202.6.129:1237)

## 1. Basic Container Testing

### 1.1 Check Container Status
```bash
# Verify container is running
docker ps | grep fluentd-snmp

# Check the SNMP trap daemon is running
docker exec fluentd-snmp-trap ps aux | grep snmptrapd
```

### 1.2 Check Configuration
```bash
# Verify the SNMP trap daemon configuration 
docker exec fluentd-snmp-trap cat /etc/snmp/snmptrapd.conf

# Check the format script
docker exec fluentd-snmp-trap cat /usr/local/bin/format-trap.sh
```

## 2. Testing SNMPv2c Functionality

### 2.1 Send a Test SNMPv2c Trap
```bash
# Send a test trap with a unique identifier
snmptrap -v 2c -c public localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 \
  1.3.6.1.2.1.1.3.0 s "TEST-V2C-$(date +%s)" 2>/dev/null
```

### 2.2 Verify Trap Reception
```bash
# Check if the trap was logged
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5
```

### 2.3 Verify Fluentd Processing
```bash
# Check if fluentd processed the message
docker logs fluentd-snmp-trap --tail 10 | grep "messages send"
```

## 3. Testing SNMPv3 Functionality

### 3.1 Send a Test SNMPv3 Trap
```bash
# Send a test SNMPv3 trap with a unique identifier
snmptrap -v 3 -u NCEadmin -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 \
  1.3.6.1.2.1.1.3.0 s "TEST-V3-$(date +%s)" 2>/dev/null
```

### 3.2 Verify Trap Reception
```bash
# Check if the SNMPv3 trap was logged
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 5
```

## 4. Testing UDP Forwarding

### 4.1 Send a Direct Test Message
```bash
# Send a test message directly to the UDP destination
echo "<snmp_trap><timestamp>$(date)</timestamp><test>direct</test><data>Test message</data></snmp_trap>" | \
  nc -u 165.202.6.129 1237
```

### 4.2 Verify at Destination
The message should be received at 165.202.6.129 on port 1237. You'll need to check at the destination to verify receipt.

## 5. Testing Full Pipeline

### 5.1 Send a Tagged SNMP Trap
```bash
# Send an SNMP trap with a unique and easily identifiable tag
UNIQUE_ID="FULL-TEST-$(date +%s)"
snmptrap -v 2c -c public localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 \
  1.3.6.1.2.1.1.3.0 s "$UNIQUE_ID" 2>/dev/null
```

### 5.2 Check Each Stage
```bash
# 1. Check trap reception
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$UNIQUE_ID"

# 2. Check fluentd processing
docker logs fluentd-snmp-trap --tail 10 | grep "messages send"

# 3. Check at destination (verification needed at 165.202.6.129:1237)
```

## 6. Troubleshooting SNMPv3 Issues

If SNMPv3 traps are not being received, try the following steps:

### 6.1 Find the Engine ID
```bash
# Method 1: Check for any persistent config
docker exec fluentd-snmp-trap find / -name snmpapp.conf -o -name snmptrapd.boot 2>/dev/null

# Method 2: Look for generated files 
docker exec fluentd-snmp-trap ls -la /var/lib/snmp/ 2>/dev/null

# Method 3: Use a debug startup
docker exec fluentd-snmp-trap sh -c "snmptrapd -Dusm,9 -f 2>&1 | grep -i engine" 
```

### 6.2 Update Configuration with Engine ID
Once you find the Engine ID, update the configuration with:
```bash
cat > updated-config.conf << EOF
# SNMPv3 configuration with specific Engine ID
createUser -e 0xACTUAL_ENGINE_ID NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata
authUser log,execute NCEadmin authPriv
authCommunity log,execute public
disableAuthorization yes
traphandle default /usr/local/bin/format-trap.sh
EOF

# Apply the updated configuration
cat updated-config.conf | docker exec -i fluentd-snmp-trap tee /etc/snmp/snmptrapd.conf

# Restart the container
docker-compose restart fluentd-snmp
```

### 6.3 Test with the Updated Engine ID
```bash
# Send a test trap with the specific Engine ID
snmptrap -v 3 -e 0xACTUAL_ENGINE_ID -u NCEadmin -a SHA -A P@ssw0rdauth \
  -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "ENGINE-ID-TEST" 2>/dev/null
```

## SNMPv3 Testing Procedure with Engine ID

## Introduction
When using SNMPv3, the Engine ID must match between the sender and receiver. This document outlines the procedures for discovering the Engine ID and running tests with the correct Engine ID.

## Engine ID Discovery

1. **Using snmpwalk to discover Engine ID**:
   ```
   snmpwalk -v 3 -u NCEadmin -l noAuthNoPriv -On localhost:1161 1.3.6.1.6.3.10.2.1.1
   ```
   This will typically return something like:
   ```
   .1.3.6.1.6.3.10.2.1.1.0 = Hex-STRING: 80 00 1F 88 80 BE 85 28 0D 02 3F 07 68 00 00 00 00
   ```
   The hex string is the Engine ID.

2. **Using packet capture**:
   ```
   tcpdump -i lo -n -s 0 port 1162 -X
   ```
   Then send a test trap and look for the Engine ID in the packet dump.

3. **Using the debug mode**:
   ```
   docker exec -it fluentd-snmp-trap sh -c "snmptrapd -Dtoken,engineID -f" 2>&1 | grep -i "engineID"
   ```

## Testing with the Correct Engine ID

1. Create a test file that uses the discovered Engine ID:
   ```bash
   #!/bin/bash
   # The discovered Engine ID
   ENGINE_ID="0x80001f8880be85280d023f076800000000"
   
   # Send trap with the matched Engine ID
   snmptrap -v 3 -e $ENGINE_ID -u NCEadmin \
     -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
     -l authPriv localhost:1162 '' \
     1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "Test with Engine ID"
   ```

2. Execute the script and check logs:
   ```
   docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 10
   ```

## Fallback to SNMPv2c

If SNMPv3 with Engine ID is too difficult to configure, you can use SNMPv2c which doesn't have Engine ID requirements:

```bash
snmptrap -v 2c -c public localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 \
  1.3.6.1.2.1.1.3.0 s "SNMPv2c Test"
```

## Engine ID Configuration

If you want to manually set the Engine ID in the configuration:

1. Edit the `/etc/snmp/snmptrapd.conf` file:
   ```
   createUser -e 0x80001f8880be85280d023f076800000000 NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata
   authUser log,execute NCEadmin authPriv
   ```

2. Restart the trap daemon:
   ```
   docker-compose restart fluentd-snmp
   ```

## Important Notes

1. The Engine ID format is typically: `0x[enterprise OID][format][text]`
2. The Engine ID must be exactly the same on both sides for SNMPv3 authentication to work
3. If you're having persistent issues with Engine ID matching, consider:
   - Using SNMPv2c for testing (less secure but easier to set up)
   - Setting a fixed Engine ID in both the sender and receiver configurations
   - Using packet capture to verify the actual Engine ID being sent

## Conclusion

This testing procedure verifies:
1. Basic container functionality
2. SNMPv2c trap reception
3. SNMPv3 trap reception (if configured properly)
4. UDP forwarding to 165.202.6.129:1237 
5. The full processing pipeline from SNMP trap reception to UDP forwarding 

# SNMPv3 Testing Procedure with Engine IDs

This document outlines the process for testing SNMPv3 with Engine IDs, including discovery methods and troubleshooting steps.

## Understanding Engine IDs

An SNMP Engine ID is a unique identifier for an SNMP entity. For SNMPv3, it's required for:
- Message authentication
- Message encryption
- Identifying the origin of notifications (traps)

## Engine ID Discovery Methods

### Method 1: Using snmpwalk (Automatic)

```bash
snmpwalk -v 3 -l noAuthNoPriv -u <username> <hostname>
```

This will typically fail with an error message containing the Engine ID:
```
snmpwalk: Authentication failure (incorrect password, community or key)
Engine ID: 80:00:1F:88:80:XX:XX:XX:XX:XX
```

### Method 2: Using snmpget with engineID option

```bash
snmpget -v 3 -E <known_engineID> -l authPriv -u <username> -a SHA -A <auth_pass> -x AES -X <priv_pass> <hostname> SNMPv2-MIB::sysDescr.0
```

### Method 3: Check SNMP configuration files

Check the snmpd.conf file for Engine ID configuration:
```bash
grep engineID /etc/snmp/snmpd.conf
```

## Testing SNMPv3 Traps with Engine ID

### 1. Configure the trap sender

```bash
# Format: snmptrap -v 3 -e <engineID> [auth options] <hostname>:<port> ... [trap parameters]
snmptrap -v 3 -e <engineID> -l authPriv -u <username> -a SHA -A <auth_pass> -x AES -X <priv_pass> <hostname>:<port> '' SNMPv2-MIB::coldStart.0
```

### 2. Configure the trap receiver (snmptrapd)

Edit `/etc/snmp/snmptrapd.conf`:
```
createUser -e <engineID> <username> SHA <auth_pass> AES <priv_pass>
authUser log,execute,net <username>
```

### 3. Start the trap receiver (if not running as a service)

```bash
snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf
```

## Troubleshooting SNMPv3 Engine ID Issues

### Authentication Failure

If you see "Authentication failure" errors:
1. Verify the Engine ID is correct
2. Check username, authentication type, and passwords
3. Ensure the Engine ID format is correct (typically hexadecimal with or without 0x prefix)

### No Traps Received

1. Verify trap receiver is running and listening on the correct port
2. Check firewall rules to ensure the port is open
3. Verify the trap sender is using the correct Engine ID of the receiver

### Engine ID Format Issues

Engine IDs can be represented in different formats:
- Hexadecimal with 0x prefix: 0x8000...
- Hexadecimal with colons: 80:00:...
- Plain hexadecimal: 8000...

Ensure you're using the format expected by your specific SNMP implementation.

## Fallback to SNMPv2c

If SNMPv3 with Engine ID troubleshooting becomes too complex, you can temporarily test with SNMPv2c:

```bash
# Send trap
snmptrap -v 2c -c public <hostname>:<port> '' SNMPv2-MIB::coldStart.0

# Configure receiver
echo "rocommunity public" > /etc/snmp/snmpd.conf
echo "authCommunity log,execute,net public" > /etc/snmp/snmptrapd.conf
```

## References

- [Net-SNMP Documentation](http://www.net-snmp.org/docs/)
- [RFC 3411 - SNMP Architecture](https://tools.ietf.org/html/rfc3411)
- [RFC 3412 - Message Processing](https://tools.ietf.org/html/rfc3412) 