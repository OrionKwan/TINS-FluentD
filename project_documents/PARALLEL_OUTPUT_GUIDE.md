# SNMP Trap Parallel Output Configuration Guide

This document explains how the fluentd-snmp container is configured for parallel output of SNMP traps to both Kafka and UDP endpoints.

## Architecture Overview

The data flow in the fluentd-snmp container follows this path:

1. **SNMP Trap Reception**: External SNMP traps are received by `snmptrapd` daemon on UDP port 1162
2. **Trap Processing**: Traps are processed by the format-trap.sh script and logged to `/var/log/snmptrapd.log`
3. **Fluentd Input**: The log file is read by Fluentd's tail plugin
4. **Parallel Processing**: The same data is sent to multiple outputs simultaneously using the copy output plugin
5. **Multi-destination Delivery**: Data is sent to both Kafka and a UDP endpoint

## Configuration Components

### 1. Input Configuration

```xml
<source>
  @type tail
  @id in_snmp_trap
  path /var/log/snmptrapd.log
  tag snmp.trap
  pos_file /tmp/snmptrapd.pos
  read_from_head true
  
  <parse>
    @type regexp
    expression /^(SNMPTRAP: |FORMATTED: )(?<message>.*)/
  </parse>
</source>
```

This configuration:
- Tails the log file where SNMP traps are logged
- Tags all events with `snmp.trap`
- Uses regex to extract the message content

### 2. Fan-out Configuration

```xml
<match snmp.trap>
  @type copy
  <store>
    # Kafka Output
    @type kafka2
    @id out_kafka
    brokers "#{ENV['KAFKA_BROKER'] || 'kafka:9092'}"
    topic "#{ENV['KAFKA_TOPIC'] || 'snmp_traps'}"
    
    <format>
      @type json
    </format>
    
    <buffer tag,time>
      @type file
      path /fluentd/buffer/kafka
      flush_mode interval
      flush_interval 5s
      retry_type exponential_backoff
      retry_wait 1s
      retry_max_interval 60s
      retry_forever true
      chunk_limit_size 64m
    </buffer>
  </store>
  
  <store>
    # UDP Output
    @type udp
    @id out_udp
    host "#{ENV['UDP_FORWARD_HOST'] || '165.202.6.129'}"
    port "#{ENV['UDP_FORWARD_PORT'] || '1237'}"
    message_format <snmp_trap><timestamp>%{time}</timestamp><version>SNMPv3</version><data>%{message}</data></snmp_trap>
    socket_buffer_size 16777216
    send_timeout 10
    ignore_error true
  </store>
</match>
```

This configuration:
- Uses the `copy` output plugin to send identical data to multiple destinations
- Configures a Kafka output with file buffering and retry logic
- Configures a UDP output with custom message format
- Sets both to process the same `snmp.trap` tagged events

### 3. Error Handling

```xml
<label @ERROR>
  <match **>
    @type file
    @id out_error_file
    path /fluentd/log/error_%Y%m%d.log
    append true
    <format>
      @type json
    </format>
    <buffer time>
      @type file
      path /fluentd/buffer/error
      flush_mode interval
      flush_interval 5s
    </buffer>
  </match>
</label>
```

This configuration:
- Captures any errors that occur in any output plugin
- Writes these errors to daily log files
- Uses file buffering for error logs

## Environment Variables

The following environment variables can be set to configure the outputs:

| Variable | Description | Default |
|----------|-------------|---------|
| `KAFKA_BROKER` | Kafka broker address | `kafka:9092` |
| `KAFKA_TOPIC` | Kafka topic for SNMP traps | `snmp_traps` |
| `UDP_FORWARD_HOST` | UDP destination host | `165.202.6.129` |
| `UDP_FORWARD_PORT` | UDP destination port | `1237` |
| `SNMPV3_ENGINE_ID` | SNMPv3 Engine ID | `0x80001F88807C0F9A615F4B0768000000` |

## Buffer and Retry Configuration

### Kafka Output
- **Buffer Type**: File-based
- **Buffer Path**: `/fluentd/buffer/kafka`
- **Flush Interval**: 5 seconds
- **Retry Strategy**: Exponential backoff
- **Initial Retry Wait**: 1 second
- **Max Retry Interval**: 60 seconds
- **Retry Policy**: Retry forever
- **Chunk Size Limit**: 64MB

### UDP Output
- **Socket Buffer Size**: 16MB
- **Send Timeout**: 10 seconds
- **Error Handling**: Ignore errors (will not block other outputs)

## Testing the Configuration

### Basic Testing

1. Run the basic test script to verify proper operation:
   ```
   ./test-parallel-output.sh
   ```
   This test verifies that:
   - SNMP traps are properly received
   - The messages are processed by Fluentd
   - No errors are reported

2. Monitor the pipeline in real-time:
   ```
   ./monitor-snmp-pipeline.sh
   ```
   This provides a live view of:
   - Container status
   - Buffer file status
   - Recent SNMP traps
   - Fluentd logs
   - Error detection

3. Send a manual test SNMP trap:
   ```
   docker exec fluentd-snmp-trap snmptrap -v 3 -e 0x80001F88807C0F9A615F4B0768000000 -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata -l authPriv localhost:1162 '' 1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "TEST-MESSAGE"
   ```

### Advanced Testing

#### Full Pipeline Test

Verifies the entire pipeline from SNMP trap reception to delivery at both outputs:

```
./test-full-pipeline.sh
```

This comprehensive test:
1. Sets up a local UDP listener to catch forwarded traps
2. Temporarily redirects the UDP output to our test listener
3. Configures a Kafka consumer to verify message delivery
4. Sends a test trap through the entire pipeline
5. Verifies reception at each stage of the pipeline
6. Restores the original configuration

#### Load Testing

Tests if the pipeline can handle the required throughput:

```
./load-test-pipeline.sh [trap_count] [parallel_processes]
```

This load test:
1. Creates multiple processes to send traps in parallel
2. Measures the throughput rate
3. Verifies if the pipeline meets the required 50k events/second throughput
4. Monitors memory usage and buffer status

Example for sending 10,000 traps with 20 parallel processes:
```
./load-test-pipeline.sh 10000 20
```

#### Chaos Testing

Tests the pipeline's resilience when destinations are unavailable:

```
./chaos-test-pipeline.sh
```

This test simulates three failure modes:
1. **Kafka Outage**: Disconnects Kafka from the network
2. **UDP Endpoint Unavailable**: Points UDP output to an unreachable endpoint
3. **Complete Outage**: Both Kafka and UDP destinations are unavailable

For each scenario, the test:
- Sends test traps during the outage
- Verifies proper buffer usage and error handling
- Restores the service and checks message delivery
- Confirms the pipeline maintains at-least-once delivery semantics

## Troubleshooting

- **Buffer Files**: Check `/fluentd/buffer/` directories for any chunk files that aren't being processed
- **Error Logs**: Check `/fluentd/log/error_*.log` files for output errors
- **Fluentd Logs**: View with `docker logs fluentd-snmp-trap`
- **SNMP Trap Logs**: Check `/var/log/snmptrapd.log` inside the container

### Common Issues and Solutions

1. **UDP Connection Failures**
   - Error: "Connection refused" in UDP output logs
   - Solution: Verify the UDP endpoint is reachable and listening on the configured port

2. **Kafka Connection Issues**
   - Error: "Connection timed out for Kafka broker" in logs
   - Solution: Ensure Kafka is running and accessible from the fluentd-snmp container

3. **Buffer Overflow**
   - Symptom: Large number of buffer files in `/fluentd/buffer/kafka`
   - Solution: Increase buffer size or check Kafka connection

4. **Missing SNMP Traps**
   - Symptom: Traps sent but not appearing in `/var/log/snmptrapd.log`
   - Solution: Verify the Engine ID in the trap matches the container's configuration 