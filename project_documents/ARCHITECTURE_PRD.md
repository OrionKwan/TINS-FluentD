# SNMP Trap Processing System Architecture PRD

## 1. Overview

This document describes the architecture of the SNMP Trap Processing System - a solution for receiving, processing, and forwarding SNMP trap messages from network devices. The system is designed to receive SNMPv3 traps securely, process them, and forward the data to multiple destinations including Kafka and external systems via UDP.

## 2. System Components

### 2.1 Core Services

The system consists of the following core components:

1. **fluentd-snmp**: Container responsible for receiving SNMP traps
   - Uses net-snmp tools for SNMP trap reception
   - Implements SNMPv3 authentication and encryption
   - Formats and forwards trap data

2. **Kafka**: Message broker for trap data distribution
   - Receives processed trap data
   - Enables multiple consumers to access the trap data
   - Provides buffering for high volume periods

3. **OpenSearch Cluster**: Analytics and storage platform
   - Two-node cluster for redundancy
   - Stores processed SNMP trap data
   - Provides search and analytics capabilities

4. **OpenSearch Dashboards**: Visualization interface
   - Web UI for data exploration and visualization
   - Creates dashboards for monitoring SNMP events
   - User interface for analysts

5. **Kafka Connect**: Data integration service
   - Connects Kafka to OpenSearch
   - Configurable via REST API
   - Transforms data as needed

6. **ML Pipeline**: Machine learning processing service
   - Processes trap data for anomaly detection
   - Connects to both Kafka and OpenSearch
   - Provides advanced analytics on trap data

### 2.2 Network Configuration

The system uses a sophisticated network setup:

1. **Docker Bridge Network (opensearch-net)**: 
   - Internal network for container communication
   - Connects all services in the docker-compose stack

2. **Docker Macvlan Network (snmpmacvlan)**:
   - External network with subnet 192.168.8.0/24
   - Provides a dedicated IP (192.168.8.100) for the fluentd-snmp container
   - Enables direct network connectivity

3. **IP Tables Forwarding**:
   - Routes external SNMP traffic to the container
   - Bridges physical and virtual networks
   - Configured via iptables-rules.sh

## 3. Component Architecture

### 3.1 fluentd-snmp Container

**Purpose**: Receives and processes SNMP traps, forwards to Kafka and other destinations.

**Main Components**:
- **snmptrapd**: Daemon that listens for SNMP traps
- **Fluentd**: Data collector that processes and forwards trap data
- **Custom Plugins**: Specialized processing for SNMP data
- **MIB Files**: SNMP MIB definitions for trap interpretation

**File Structure**:
- `/fluentd-snmp/Dockerfile`: Container build definition
- `/fluentd-snmp/conf/`: Configuration files
  - `fluent.conf`: Fluentd pipeline configuration
  - `snmptrapd.conf`: SNMP trap daemon configuration
- `/fluentd-snmp/plugins/`: Custom Fluentd plugins
- `/fluentd-snmp/mibs/`: SNMP MIB definitions
- `/fluentd-snmp/entrypoint.sh`: Container startup script

### 3.2 Data Flow Architecture

1. **SNMP Trap Reception**:
   - External device sends trap to 192.168.8.30:1162
   - Trap is forwarded via iptables to fluentd-snmp container
   - snmptrapd receives and authenticates the trap

2. **Trap Processing**:
   - Trap data is logged to `/var/log/snmptrapd.log`
   - Fluentd reads the log file using the `tail` input plugin
   - Data is parsed and structured

3. **Data Distribution**:
   - Processed trap data is sent to Kafka
   - Copy of data is forwarded via UDP to external systems
   - Debug information is logged for troubleshooting

## 4. Configuration Architecture

### 4.1 Environment Variables

The system uses environment variables in docker-compose.yml for configuration:

**SNMP Authentication**:
- `SNMPV3_USER`: SNMPv3 username
- `SNMPV3_AUTH_PROTOCOL`: Authentication protocol (SHA)
- `SNMPV3_AUTH_PASS`: Authentication password
- `SNMPV3_PRIV_PROTOCOL`: Privacy protocol (AES)
- `SNMPV3_PRIV_PASS`: Privacy password
- `SNMPV3_ENGINE_ID`: Engine ID for SNMPv3 authentication

**Network Configuration**:
- `SNMP_BIND_INTERFACE`: Network interface to bind
- `KAFKA_BROKER`: Kafka connection endpoint
- `KAFKA_TOPIC`: Destination topic for trap data
- `UDP_FORWARD_HOST`: External UDP destination
- `UDP_FORWARD_PORT`: UDP forwarding port

### 4.2 Configuration Files

**Fluentd Configuration**:
- Input section: Reads log file and parses trap data
- Processing section: Formats and enriches trap data
- Output section: Sends to Kafka, UDP forward, and stdout
- Error handling: Captures and logs processing errors

**SNMP Configuration**:
- SNMPv3 user creation
- Authentication and privacy settings
- Authorization rules
- Log formatting directives

## 5. Deployment Architecture

### 5.1 Docker Compose Deployment

The entire system is deployed using Docker Compose with the following services:

1. **Zookeeper**: Coordination service for Kafka
2. **Kafka**: Message broker
3. **Kafka Connect**: Data integration service
4. **OpenSearch Node 1**: Primary search node
5. **OpenSearch Node 2**: Secondary search node
6. **OpenSearch Dashboards**: UI component
7. **ML Pipeline**: Machine learning service
8. **fluentd-snmp**: SNMP trap processing service

### 5.2 Volume Management

The system uses Docker volumes for data persistence:

- `opensearch-data1`: Data for OpenSearch node 1
- `opensearch-data2`: Data for OpenSearch node 2

### 5.3 Network Management

Two Docker networks are defined:
- `opensearch-net`: Internal bridge network
- `snmpmacvlan`: External network (pre-created)

## 6. Maintenance and Operations

### 6.1 Scripts and Utilities

The project includes several maintenance and testing scripts:

1. **iptables-rules.sh**: Configures network forwarding rules
2. **configure-snmptrapd.sh**: Configures the SNMP trap daemon
3. **send-test-trap.sh**: Sends test SNMP traps for validation
4. **check-traps.sh**: Verifies trap reception and processing
5. **extract-engine-id.sh**: Extracts SNMP engine IDs from network captures
6. **capture-snmpv3-trap.sh**: Captures SNMP trap traffic

### 6.2 Monitoring and Debugging

The system provides several monitoring mechanisms:

1. **Log Files**:
   - `/var/log/snmptrapd.log`: Raw trap reception logs
   - `/fluentd/log/fluentd.log`: Fluentd processing logs
   - `/fluentd/log/error_YYYYMMDD.log`: Error logs

2. **Health Checks**:
   - Docker health check for snmptrapd process
   - OpenSearch cluster health monitoring

## 7. Testing Procedures

Testing procedures are documented in `fluentd-snmp/TESTING_PROCEDURE.md` and include:

1. **Unit Testing**: Testing individual components
2. **Integration Testing**: Testing component interactions
3. **End-to-End Testing**: Testing the complete flow
4. **Performance Testing**: Testing under load

## 8. Security Architecture

The system implements several security measures:

1. **SNMPv3 Authentication and Privacy**:
   - SHA authentication
   - AES encryption
   - User-based security model

2. **Network Isolation**:
   - Docker networks for service isolation
   - Macvlan for dedicated network interface

3. **OpenSearch Security**:
   - Password protection
   - HTTPS communication

## 9. Conclusion

This SNMP Trap Processing System provides a comprehensive solution for receiving, processing, and distributing SNMP trap data. The architecture uses container orchestration, message queuing, and search technologies to create a scalable, secure, and maintainable system. 