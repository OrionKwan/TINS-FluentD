# Fluentd-SNMP Configuration Guide

This document provides a comprehensive guide to configuring the fluentd-snmp system, including all adjustable parameters for the container, snmptrapd daemon, and Fluentd plugins.

## Table of Contents

1. [Environment Variables](#environment-variables)
2. [SNMPv3 Configuration](#snmpv3-configuration)
3. [Fluentd Configuration](#fluentd-configuration)
4. [Container Configuration](#container-configuration)
5. [Network Configuration](#network-configuration)
6. [Plugin Configuration](#plugin-configuration)
7. [Advanced Configuration](#advanced-configuration)

## Environment Variables

The following environment variables can be set in the `docker-compose.yml` file to configure the fluentd-snmp container:

### SNMP Authentication Parameters

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `SNMPV3_USER` | SNMPv3 username | `NCEadmin` | `SNMPV3_USER=admin` |
| `SNMPV3_AUTH_PROTOCOL` | Authentication protocol | `SHA` | `SNMPV3_AUTH_PROTOCOL=SHA256` |
| `SNMPV3_AUTH_PASS` | Authentication password | `P@ssw0rdauth` | `SNMPV3_AUTH_PASS=MyAuthPassword` |
| `SNMPV3_PRIV_PROTOCOL` | Privacy protocol | `AES` | `SNMPV3_PRIV_PROTOCOL=AES256` |
| `SNMPV3_PRIV_PASS` | Privacy password | `P@ssw0rddata` | `SNMPV3_PRIV_PASS=MyPrivPassword` |
| `SNMPV3_ENGINE_ID` | Engine ID for SNMPv3 authentication | None | `SNMPV3_ENGINE_ID=172.29.36.80` |

### Network Parameters

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `SNMP_BIND_INTERFACE` | Network interface to bind | None | `SNMP_BIND_INTERFACE=eth1` |
| `KAFKA_BROKER` | Kafka connection endpoint | `kafka:9092` | `KAFKA_BROKER=kafka.example.com:9092` |
| `KAFKA_TOPIC` | Destination topic for trap data | `snmp_traps` | `KAFKA_TOPIC=network_events` |
| `UDP_FORWARD_HOST` | External UDP destination | `165.202.6.129` | `UDP_FORWARD_HOST=syslog.example.com` |
| `UDP_FORWARD_PORT` | UDP forwarding port | `1237` | `UDP_FORWARD_PORT=514` |

### Example Environment Configuration in docker-compose.yml

```yaml
fluentd-snmp:
  # ...
  environment:
    - SNMPV3_USER=NCEadmin
    - SNMPV3_AUTH_PASS=P@ssw0rdauth
    - SNMPV3_PRIV_PASS=P@ssw0rddata
    - SNMPV3_AUTH_PROTOCOL=SHA
    - SNMPV3_PRIV_PROTOCOL=AES
    - SNMPV3_ENGINE_ID=172.29.36.80
    - SNMP_BIND_INTERFACE=eth1
    - KAFKA_BROKER=kafka:9092
    - KAFKA_TOPIC=snmp_traps
    - UDP_FORWARD_HOST=165.202.6.129
    - UDP_FORWARD_PORT=1237
```

## SNMPv3 Configuration

The SNMPv3 configuration is automatically generated at container startup based on environment variables.

### Authentication Protocols

The `SNMPV3_AUTH_PROTOCOL` parameter supports the following protocols:

| Protocol | Description |
|----------|-------------|
| `MD5` | MD5 authentication (128-bit, less secure) |
| `SHA` | SHA-1 authentication (160-bit) |
| `SHA256` | SHA-256 authentication (256-bit, more secure) |
| `SHA512` | SHA-512 authentication (512-bit, most secure) |

### Privacy Protocols

The `SNMPV3_PRIV_PROTOCOL` parameter supports the following protocols:

| Protocol | Description |
|----------|-------------|
| `DES` | DES encryption (56-bit, less secure) |
| `AES` | AES encryption (128-bit) |
| `AES192` | AES encryption (192-bit) |
| `AES256` | AES encryption (256-bit, most secure) |

### Engine ID Configuration

The `SNMPV3_ENGINE_ID` parameter accepts:
- IP address format (e.g., `172.29.36.80`): Automatically converted to hex format `0x8000` + hex-encoded IP
- Hex format (e.g., `0x8000ac1d2450`): Used as provided
- If not specified: Net-SNMP will generate a random Engine ID

### Generated snmptrapd.conf Example

When the container starts, it generates a configuration like:

```
# SNMPv3 configuration
# Engine ID for 172.29.36.80 in hex format
createUser -e 0x8000ac1d2450 NCEadmin SHA P@ssw0rdauth AES P@ssw0rddata

# SNMPv3 auth rules
authUser log,execute,net NCEadmin authPriv
authUser log,execute,net NCEadmin authNoPriv
authUser log,execute,net NCEadmin noauth

# Accept SNMPv1/v2c traps with community string
authCommunity log,execute,net public

# Disable authorization to accept all traps
disableAuthorization yes

# Log format specification - more verbose
format1 TRAP: [%04y-%02m-%02d %02.2h:%02.2j:%02.2k] %B [%a] -> %b: %N::%W: %V
format2 TRAP: [%04y-%02m-%02d %02.2h:%02.2j:%02.2k] %B [%a] -> %b: %N::%W: %V
outputOption fts

# Log to file and stdout
logOption f,s /var/log/snmptrapd.log
```

## Fluentd Configuration

The fluentd configuration is located at `/fluentd-snmp/conf/fluent.conf` and can be customized as needed.

### Input Section

```ruby
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

Parameters that can be modified:
- `tag`: Tag to apply to events (default: `snmp.trap`)
- `path`: Path to the log file (default: `/var/log/snmptrapd.log`)
- `pos_file`: Position file to track read progress (default: `/tmp/snmptrapd.pos`)
- `read_from_head`: Whether to read from the beginning of the file (default: `true`)
- `expression`: Regular expression to parse log entries

### Output Section - Kafka

```ruby
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
    timekey 60
    timekey_wait 5s
    retry_type exponential_backoff
    retry_wait 1s
    retry_max_interval 60s
    retry_forever true
    chunk_limit_size 64m
  </buffer>
</store>
```

Parameters that can be modified:
- `brokers`: Kafka broker addresses (from `KAFKA_BROKER` environment variable)
- `topic`: Kafka topic to publish to (from `KAFKA_TOPIC` environment variable)
- `flush_interval`: How often to flush buffered events (default: `5s`)
- `chunk_limit_size`: Maximum size of buffer chunks (default: `64m`)
- `retry_forever`: Whether to retry indefinitely on failure (default: `true`)
- `retry_wait`: Initial wait time between retries (default: `1s`)
- `retry_max_interval`: Maximum interval between retries (default: `60s`)

### Output Section - UDP Forwarding

```ruby
<store>
  # UDP Output
  @type tagged_udp
  @id out_tagged_udp
  host "#{ENV['UDP_FORWARD_HOST'] || '165.202.6.129'}"
  port "#{ENV['UDP_FORWARD_PORT'] || '1237'}"
  
  <format>
    @type json
  </format>
</store>
```

Parameters that can be modified:
- `host`: UDP destination host (from `UDP_FORWARD_HOST` environment variable)
- `port`: UDP destination port (from `UDP_FORWARD_PORT` environment variable)
- `format`: Output format (default: `json`)

### Error Handling

```ruby
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

Parameters that can be modified:
- `path`: Path to error log file (default: `/fluentd/log/error_%Y%m%d.log`)
- `flush_interval`: How often to flush error logs (default: `5s`)

### Global Configuration

```ruby
<s>
  log_level info
  log_path /fluentd/log/fluentd.log
</s>
```

Parameters that can be modified:
- `log_level`: Logging level (options: `fatal`, `error`, `warn`, `info`, `debug`, `trace`)
- `log_path`: Path to Fluentd log file

## Container Configuration

The container configuration is defined in `/fluentd-snmp/Dockerfile`.

### Installed Plugins

The following Fluentd plugins are installed:
- `fluent-plugin-kafka` (v0.19.4): For sending data to Kafka
- `fluent-plugin-remote_syslog` (v1.1.0): For remote syslog support
- `fluent-plugin-record-modifier` (v2.2.0): For record modification
- `fluent-plugin-tagged_udp`: For tagged UDP output

To modify installed plugins, edit the Dockerfile:

```dockerfile
RUN apk add --no-cache build-base ruby-dev && \
    gem install msgpack -v "~> 1.4" && \
    gem install snmp && \
    gem install fluent-plugin-kafka -v 0.19.4 && \
    gem install fluent-plugin-remote_syslog -v 1.1.0 && \
    gem install fluent-plugin-record-modifier -v 2.2.0 && \
    gem install fluent-plugin-tagged_udp && \
    apk del build-base ruby-dev && \
    rm -rf /tmp/* /var/tmp/* /usr/lib/ruby/gems/*/cache/*.gem
```

### Volume Configuration

The container mounts the following volumes:
- `/fluentd-snmp/mibs:/fluentd/mibs:ro`: Custom MIB files
- `/fluentd-snmp/conf:/fluentd/etc:ro`: Configuration files

To add custom MIB files, place them in the `fluentd-snmp/mibs` directory on the host.

## Network Configuration

The container uses two networks:
- `opensearch-net`: For internal communication with Kafka
- `snmpmacvlan`: For direct network connectivity with SNMPv3 devices

### IP Tables Forwarding

To ensure SNMP traps are properly routed to the container, the following iptables rules are required:

```bash
# Forward SNMP trap traffic from host to container
iptables -t nat -I PREROUTING 1 -i ens160 -p udp --dport 1162 -j DNAT --to-destination 192.168.8.100:1162

# Remove conflicting Docker rules
iptables -t nat -D DOCKER -p udp --dport 1162 -j DNAT --to-destination 172.18.0.3:1162

# Enable masquerading for forwarded packets
iptables -t nat -A POSTROUTING -o ens160 -j MASQUERADE
```

## Plugin Configuration

The container includes a custom SNMP plugin located at `/fluentd-snmp/plugins/in_snmptrapd.rb`.

### Configurable Plugin Parameters

The following parameters can be configured:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `tag` | Tag to apply to events | `snmp.trap` |
| `port` | Port for snmptrapd to listen on | `1162` |
| `username` | Username for SNMPv3 | From `SNMPV3_USER` env |
| `auth_protocol` | Auth protocol for SNMPv3 | From `SNMPV3_AUTH_PROTOCOL` env |
| `auth_password` | Auth password for SNMPv3 | From `SNMPV3_AUTH_PASS` env |
| `priv_protocol` | Privacy protocol for SNMPv3 | From `SNMPV3_PRIV_PROTOCOL` env |
| `priv_password` | Privacy password for SNMPv3 | From `SNMPV3_PRIV_PASS` env |
| `community` | SNMP community string for v1/v2c | `public` |
| `mib_dir` | Path to MIB files | `/usr/share/snmp/mibs` |
| `mibs` | MIB files to load | `+IMAP_NORTHBOUND_MIB-V1` |
| `max_retries` | Max number of reconnection attempts | `5` |
| `retry_interval` | Delay between reconnection attempts | `5` seconds |

## Advanced Configuration

### Custom MIB Support

To add custom MIB files:

1. Place MIB files in `/fluentd-snmp/mibs` directory
2. Restart the container
3. The MIB files will be automatically loaded during startup

### Performance Tuning

For high-volume environments, consider adjusting these parameters:

1. **Buffer size and flush intervals**
   ```ruby
   <buffer tag,time>
     chunk_limit_size 128m  # Increase from 64m
     flush_interval 10s     # Increase from 5s
   </buffer>
   ```

2. **Multi-process workers**
   Add to the global configuration:
   ```ruby
   <s>
     workers 4  # Adjust based on available CPU cores
   </s>
   ```

### Troubleshooting Options

For debugging issues, modify these settings:

1. **Increase log level**
   ```ruby
   <s>
     log_level debug
   </s>
   ```

2. **Enable more verbose SNMP debugging**
   Add to docker-compose.yml:
   ```yaml
   environment:
     - SNMP_DEBUG=true
   ```

3. **Enable packet capture**
   Add to docker-compose.yml:
   ```yaml
   environment:
     - ENABLE_PACKET_CAPTURE=true
   ``` 