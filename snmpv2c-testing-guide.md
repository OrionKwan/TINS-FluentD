# fluentd-snmp Testing Guide

This guide provides instructions for testing the fluentd-snmp container's trap receiving and forwarding capabilities. Due to challenges with SNMPv3 Engine ID configuration, this guide focuses on using SNMPv2c for reliable testing.

## SNMPv2c Testing Procedure

SNMPv2c provides a simpler and more reliable way to test the fluentd-snmp container's functionality. Here's how to test with SNMPv2c:

### 1. Verify Container Status

```bash
# Check if the container is running
docker ps | grep fluentd-snmp-trap

# Check the SNMP trap daemon status
docker exec fluentd-snmp-trap ps aux | grep snmptrapd
```

### 2. Send a Test SNMPv2c Trap

```bash
# Create a unique ID for this test
TEST_ID="V2C-TEST-$(date +%s)"

# Send the trap
snmptrap -v 2c -c public localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 \
  1.3.6.1.2.1.1.3.0 s "$TEST_ID" 2>/dev/null
```

### 3. Verify Trap Reception

```bash
# Check if the trap was received and logged
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID"
```

### 4. Verify Fluentd Processing

```bash
# Check if fluentd processed and forwarded the message
docker logs fluentd-snmp-trap --tail 10 | grep "messages send"
```

### 5. Test Direct UDP Forwarding

```bash
# Send a direct UDP message to the destination
echo "<snmp_trap><timestamp>$(date)</timestamp><type>direct</type><data>Test message</data></snmp_trap>" | \
  nc -u 165.202.6.129 1237
```

## SNMPv3 Engine ID Notes

We attempted to set a custom Engine ID "12345678911" for SNMPv3, but encountered challenges:

1. Engine ID Format: The SNMP standard requires Engine IDs to follow a specific format, which can vary by implementation.

2. Attempted Approaches:
   - Direct numeric: `createUser -e 12345678911`
   - Hex representation: `createUser -e 0x3132333435363738393131`
   - ASCII conversion: Representing "12345678911" as hex bytes

3. Findings:
   - SNMPv2c works reliably for testing trap reception and forwarding
   - SNMPv3 configuration requires precise Engine ID matching between sender and receiver
   - The container appears to regenerate its Engine ID on restart

## Full Test Script

We've created a comprehensive test script that tests both SNMPv3 (which currently fails) and SNMPv2c (which works):

```bash
./test-numeric-engine.sh
```

This script:
1. Attempts an SNMPv3 trap with the custom Engine ID
2. Falls back to testing with SNMPv2c
3. Tests direct UDP forwarding to 165.202.6.129:1237

## Conclusion

For reliable testing of the fluentd-snmp container's trap reception and forwarding, we recommend using SNMPv2c. While SNMPv3 offers better security, the challenges with Engine ID configuration make SNMPv2c a more practical choice for functional testing. 