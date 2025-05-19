# SNMP Trap Capture System - Testing Procedure Guide

This guide provides step-by-step procedures for testing the SNMP trap capture and forwarding system. These tests will verify that traps are properly received, processed, and forwarded to all configured destinations.

## Prerequisites

Before beginning testing, ensure:

1. The Docker environment is running
2. The fluentd-snmp container is built and running
3. Kafka is running and accessible
4. Network connectivity to the UDP forwarding destination (165.202.6.129:1237) is available

## 1. Basic System Verification

### 1.1 Verify Container Status

```bash
# Check if container is running
docker ps | grep fluentd-snmp

# Verify logs show successful initialization
docker logs fluentd-snmp-trap | grep -E "snmptrapd is running|Starting Fluentd"
```

Expected outcome: Container is running with both snmptrapd and Fluentd started successfully.

### 1.2 Verify Process Status

```bash
# Check if snmptrapd is running inside the container
docker exec fluentd-snmp-trap ps aux | grep "[s]nmptrapd"

# Check if Fluentd is running
docker exec fluentd-snmp-trap ps aux | grep "[f]luentd"
```

Expected outcome: Both processes should be running inside the container.

## 2. SNMPv2c Trap Testing

### 2.1 Send SNMPv2c Test Trap

```bash
# Generate a unique identifier for this test
TEST_ID="V2C-$(date +%s)"

# Send SNMPv2c trap using the provided script
./send-test-trap.sh v2c "$TEST_ID"

# Alternatively, send manually (suppress MIB warnings)
SNMPCONFPATH=/tmp/snmp-no-mibs.conf snmptrap -v 2c -c public localhost:1162 -On '' \
  1.3.6.1.6.3.1.1.5.3 \
  1.3.6.1.2.1.2.2.1.1.1 i 1 \
  1.3.6.1.2.1.2.2.1.2.1 s "TEST-$TEST_ID" \
  1.3.6.1.2.1.2.2.1.7.1 i 1 \
  1.3.6.1.2.1.2.2.1.8.1 i 2
```

### 2.2 Verify Trap Reception in Logs

```bash
# Check if trap was received in log
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID"
```

Expected outcome: Log entry with the test identifier is found.

### 2.3 Verify Kafka Output

```bash
# Check if trap data reached Kafka
docker exec kafka kafka-console-consumer --bootstrap-server kafka:9092 \
  --topic snmp_traps --from-beginning --max-messages 10 | grep "$TEST_ID"
```

Expected outcome: Message with the test identifier is found in Kafka.

## 3. SNMPv3 Trap Testing

### 3.1 Send SNMPv3 Test Trap

```bash
# Generate a unique identifier for this test
TEST_ID="V3-$(date +%s)"

# Send SNMPv3 trap using the provided script
./send-test-trap.sh v3 "$TEST_ID"

# Alternatively, send manually (suppress MIB warnings)
SNMPCONFPATH=/tmp/snmp-no-mibs.conf snmptrap -v 3 -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv -u NCEadmin -e 0x0102030405 -On localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.4 \
  1.3.6.1.2.1.2.2.1.1.1 i 1 \
  1.3.6.1.2.1.2.2.1.2.1 s "TEST-$TEST_ID" \
  1.3.6.1.2.1.2.2.1.7.1 i 1 \
  1.3.6.1.2.1.2.2.1.8.1 i 1
```

### 3.2 Verify Trap Reception in Logs

```bash
# Check if trap was received in log
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID"
```

Expected outcome: Log entry with the test identifier is found.

### 3.3 Verify Kafka Output

```bash
# Check if trap data reached Kafka
docker exec kafka kafka-console-consumer --bootstrap-server kafka:9092 \
  --topic snmp_traps --from-beginning --max-messages 10 | grep "$TEST_ID"
```

Expected outcome: Message with the test identifier is found in Kafka.

## 4. XML Formatting and UDP Forwarding Testing

### 4.1 Send Trap with Formatting Test

```bash
# Generate a unique identifier for this test
TEST_ID="XML-$(date +%s)"

# Send SNMPv2c trap with specific test string
./send-test-trap.sh v2c "$TEST_ID"
```

### 4.2 Verify XML Formatting in Logs

```bash
# Check for formatted output in logs
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "FORMATTED" | grep "$TEST_ID"
```

Expected outcome: Formatted XML entry with the test identifier is found.

### 4.3 Verify UDP Output Reception

To test UDP output reception, you have several options:

#### Option A: Use netcat to listen for UDP messages

```bash
# On the UDP destination machine (165.202.6.129), run:
nc -lu 1237
```

#### Option B: Use tcpdump to capture UDP packets

```bash
# On the UDP destination machine, run:
sudo tcpdump -i any -n udp port 1237 -A
```

#### Option C: Use the direct format test script

```bash
# Send a direct formatted message
./test-direct-format.sh "This is a direct UDP test message $TEST_ID"
```

Expected outcome: UDP message with XML formatted data containing the test identifier is received.

## 5. Custom MIB Testing

### 5.1 Add Custom MIB File

```bash
# Copy a custom MIB file to the mibs directory
cp /path/to/your/CUSTOM-MIB.txt fluentd-snmp/mibs/

# Rebuild the container
./rebuild.sh
```

### 5.2 Send Trap with Custom OIDs

```bash
# Generate a unique identifier for this test
TEST_ID="MIB-$(date +%s)"

# Send a trap using OIDs from the custom MIB
./test-custom-mib-trap.sh "$TEST_ID"
```

### 5.3 Verify MIB Resolution

```bash
# Check logs for resolved OIDs
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "$TEST_ID"
```

Expected outcome: Log entry shows resolved OID names instead of numeric OIDs.

## 6. Performance Testing

### 6.1 High-Volume Trap Test

```bash
# Send multiple traps in succession
for i in $(seq 1 100); do
  ./send-test-trap.sh v2c "PERF-$i-$(date +%s)"
  sleep 0.1
done
```

### 6.2 Check Processing Rate

```bash
# Count messages in log
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep "SNMPTRAP" | wc -l

# Count messages in Kafka
docker exec kafka kafka-run-class kafka.tools.GetOffsetShell \
  --bootstrap-server kafka:9092 --topic snmp_traps --time -1
```

Expected outcome: All traps are received, processed, and forwarded without significant delays.

## 7. Error Handling Testing

### 7.1 Send Malformed SNMP Trap

```bash
# Send trap with invalid OID
snmptrap -v 2c -c public localhost:1162 '' 1.999.999 1.3.6.1.2.1.2.2.1.1.1 i 1
```

### 7.2 Check Error Handling

```bash
# Check container logs for errors
docker logs fluentd-snmp-trap | grep -i error

# Check Fluentd logs for parsing errors
docker exec fluentd-snmp-trap cat /var/log/fluentd/fluentd.log | grep -i error
```

Expected outcome: System handles malformed data gracefully without crashing.

## 8. Cleanup

```bash
# Stop all test processes
docker-compose stop fluentd-snmp kafka

# Restart for regular operation
docker-compose up -d
```

## Troubleshooting

If any tests fail, check the following:

1. **Connectivity issues**:
   - Verify network connections between components
   - Check firewall settings

2. **Authentication issues**:
   - Verify SNMPv3 credentials are correct
   - Check community string for SNMPv2c

3. **Process issues**:
   - Restart the container using `./rebuild.sh`
   - Check logs for error messages

4. **Kafka issues**:
   - Verify Kafka broker is running
   - Check topic exists and is accessible

5. **UDP forwarding issues**:
   - Verify target host is reachable
   - Check that port 1237 is open and accepting connections

## Test Result Documentation

For each test, document:

1. Test date and time
2. Test identifier used
3. Commands executed
4. Actual results observed
5. Pass/Fail status
6. Any discrepancies or issues noted

Use this format for test reporting:

```
Test: [Test Number and Name]
Date: YYYY-MM-DD HH:MM
Tester: [Name]
Test ID: [Identifier used]
Commands:
  [Commands executed]
Results:
  [Observed outcomes]
Status: [PASS/FAIL]
Notes:
  [Additional observations or issues]
```

Maintain a test log for all verification activities to track system performance over time. 