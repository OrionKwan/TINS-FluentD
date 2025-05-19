# Fluentd SNMPv3 Trap Receiver

A Fluentd plugin to receive and parse SNMPv3 traps, with support for forwarding to Kafka.

## Features

- Full SNMPv3 support with various authentication and privacy protocols
- Support for legacy SNMPv1/v2c traps
- Automatic trap parsing and structured output
- Integration with Kafka for streaming trap data
- Support for custom MIBs
- Comprehensive error handling and logging 

## Usage

### Container Setup
The container is configured to:
1. Create the SNMPv3 user
2. Start snmptrapd listening on port 1162
3. Start Fluentd with the configured plugins

### Testing Traps
A script is provided to test sending traps without MIB resolution warnings:

```bash
# Run the test script
./send-test-trap.sh
```

The script sends both SNMPv2c and SNMPv3 traps to the container.

### Checking Results
To check if traps are being processed correctly:

```bash
# Run the check script
./check-traps.sh
```

This will show:
- The latest entries in the SNMP trap log
- Fluentd processing logs
- Messages sent to Kafka

### Manual SNMP Trap Commands

#### SNMPv2c Trap
```bash
# Without MIB resolution warnings
SNMPCONFPATH=/tmp/snmp-no-mibs.conf snmptrap -v 2c -c public localhost:1162 -On '' 1.3.6.1.6.3.1.1.5.3 1.3.6.1.2.1.2.2.1.1.1 i 1 1.3.6.1.2.1.2.2.1.2.1 s "TEST-TRAP" 1.3.6.1.2.1.2.2.1.7.1 i 1 1.3.6.1.2.1.2.2.1.8.1 i 2
```

#### SNMPv3 Trap
```bash
# Without MIB resolution warnings
SNMPCONFPATH=/tmp/snmp-no-mibs.conf snmptrap -v 3 -a SHA -A P@ssw0rdauth -x AES -X P@ssw0rddata -l authPriv -u NCEadmin -e 0x0102030405 -On localhost:1162 '' 1.3.6.1.6.3.1.1.5.4 1.3.6.1.2.1.2.2.1.1.1 i 1 1.3.6.1.2.1.2.2.1.2.1 s "TEST-TRAP-V3" 1.3.6.1.2.1.2.2.1.7.1 i 1 1.3.6.1.2.1.2.2.1.8.1 i 1
```

## Configuration Files

### trap-handler Script
The container uses a custom trap handler script that:
1. Receives trap data from snmptrapd
2. Adds timestamps to each line
3. Formats the output for Fluentd parsing

### Fluentd Configuration
The Fluentd configuration:
1. Reads the trap log file
2. Parses each line with timestamps
3. Adds device and trap type information
4. Sends data to three destinations:
   - Kafka (JSON format)
   - Remote Syslog (UDP)
   - Standard output (for debugging)

## Configuration

### Environment Variables

Configure the plugin using the following environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `SNMPV3_USER` | SNMPv3 username | `NCEadmin` |
| `SNMPV3_AUTH_PROTOCOL` | Authentication protocol (SHA, SHA256, SHA512, MD5) | `SHA` |
| `SNMPV3_AUTH_PASS` | Authentication password | `P@ssw0rdauth` |
| `SNMPV3_PRIV_PROTOCOL` | Privacy protocol (AES, AES192, AES256, DES) | `AES` |
| `SNMPV3_PRIV_PASS` | Privacy password | `P@ssw0rddata` |
| `SNMP_COMMUNITY` | Community string for SNMPv1/v2c | `public` |
| `KAFKA_BROKER` | Kafka broker address | `kafka:9092` |
| `KAFKA_TOPIC` | Kafka topic for trap messages | `snmp_traps` |

### Fluentd Configuration

```
<source>
  @type snmptrapd
  bind 0.0.0.0
  port 1162
  
  # SNMPv3 configuration
  username "#{ENV['SNMPV3_USER']}"
  auth_protocol "#{ENV['SNMPV3_AUTH_PROTOCOL']}"
  auth_password "#{ENV['SNMPV3_AUTH_PASS']}"
  priv_protocol "#{ENV['SNMPV3_PRIV_PROTOCOL']}"
  priv_password "#{ENV['SNMPV3_PRIV_PASS']}"
  
  tag snmp.trap
</source>
```

## Testing

A test script is included to send test SNMPv3 traps:

```bash
./test-snmpv3-trap.sh
```

You can override default settings using environment variables:

```bash
TRAP_DESTINATION=192.168.1.100 TRAP_PORT=1162 ./test-snmpv3-trap.sh
```

## Plugin Architecture

The plugin uses the `snmptrapd` daemon from net-snmp to receive traps and processes them in Fluentd. The flow is:

1. SNMPv3 traps are received by snmptrapd
2. Our plugin parses the trap data into structured records
3. Fluentd processes and forwards these records to configured outputs (Kafka, file, etc.)

## Troubleshooting

### Common Issues

1. **Authentication failures**: Verify your SNMPv3 username, auth protocol and passwords
2. **Missing traps**: Check that the port (default: 1162) is accessible and not blocked by firewalls
3. **Parsing errors**: Try enabling debug logging to see raw trap content

### Debug Logging

Enable debug logging by adding to fluent.conf:

```
<system>
  log_level debug
</system>
```

## MIB Support

Place custom MIB files in the `/fluentd/mibs` directory. They will be automatically loaded.

## Custom MIB Support and XML Formatting

The container is configured to handle custom MIBs and format trap data as XML for web applications:

### Adding Custom MIB Files

1. Place your custom MIB files in the `fluentd-snmp/mibs/` directory
2. Rebuild the container using `./rebuild.sh`
3. The MIB files will be automatically loaded when the container starts

### XML Formatted Output

Trap data is formatted as XML with the following structure:

```xml
<snmp_trap>
  <timestamp>2023-01-01 12:00:00</timestamp>
  <device>192.168.1.10</device>
  <type>linkDown</type>
  <data>Original trap data with OIDs</data>
</snmp_trap>
```

This formatted data is sent to:
1. Kafka (as part of the JSON record)
2. Remote syslog via UDP (as plain XML text)
3. Container logs (for debugging)

### Testing with Custom MIBs

Use the provided script to test with custom MIBs:

```bash
# Send a test trap using custom MIBs
./test-custom-mib-trap.sh
```

### Verifying XML Output

Check the formatted output:

```bash
# Check formatted XML in the log
docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | grep FORMATTED

# Check Kafka for formatted output
docker exec kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic snmp_traps --from-beginning | grep formatted_output
```

### Web Application Integration

Your web application should be configured to:
1. Listen for UDP messages on the configured port (default: 5140)
2. Parse the incoming XML data
3. Process the trap information as needed

## License

MIT 

### Dealing with MIB Warnings

When sending SNMP traps, you might see warnings like:
```
Cannot find module (UCD-DISKIO-MIB): At line 1 in (none)
Cannot adopt OID in LM-SENSORS-MIB: lmSensors ::= { ucdExperimental 16 }
```

These warnings occur because:
1. The basic SNMP tools are installed, but without all the optional MIB files
2. The local user doesn't have permission to write to the /var/lib/snmp directory

The provided `send-test-trap.sh` script suppresses these warnings by:
1. Creating a temporary configuration file that disables MIB loading
2. Redirecting error output to /dev/null
3. Using simple numeric OIDs where possible

If you need to install MIB files permanently, you can use:
```bash
sudo apt-get install snmp-mibs-downloader
``` 