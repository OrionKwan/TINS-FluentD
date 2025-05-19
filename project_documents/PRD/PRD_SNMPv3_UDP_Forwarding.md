# Product Requirements Document: SNMPv3 Trap UDP Forwarding Solution

## 1. Introduction & Overview

### 1.1. Purpose of this Document
This document outlines the product requirements for the SNMPv3 Trap UDP Forwarding Solution. Its purpose is to define the scope, features, and objectives of this initiative, ensuring alignment among stakeholders and guiding the development and deployment process.

### 1.2. Problem Statement
Our existing SNMP trap processing pipeline faced a critical issue where SNMP traps, specifically when forwarded via UDP by Fluentd, were failing due to a message formatting error related to the `%{time}` placeholder. This resulted in incomplete data delivery to essential monitoring and analytics systems, impacting operational visibility.

### 1.3. Proposed Solution
The SNMPv3 Trap UDP Forwarding Solution addresses this issue by implementing a reconfigured and robust Fluentd-based service. This service accurately ingests SNMPv3 traps, processes them, and reliably forwards them to two key destinations: our Kafka infrastructure and a designated external UDP endpoint (`165.202.6.129:1237`). The solution is containerized using Docker for consistent deployment and integrates with our existing network stack.

### 1.4. System Architecture Diagram
The following diagram illustrates the data flow and components of the SNMPv3 Trap UDP Forwarding solution:

```mermaid
graph TD
    A[External SNMP Traps] --> |UDP Port 1162| B[SNMPTRAPD]
    B1[SNMPv3 User: NCEadmin] --> |SHA Auth, AES Priv| B
    B2[SNMPv2c Community: public] --> B
    B --> |Writes formatted traps| C[/var/log/snmptrapd.log]
    C --> |tail plugin| D[Fluentd Source]
    D --> |regexp parser| E[Extract trap data]
    E --> |record_transformer| F[Enhance with metadata]
    F --> |copy plugin| G[Multiple Output Routing]
    G --> |debug output| H[Stdout JSON Format]
    G --> |remote_syslog plugin| I[Syslog Formatted Output]
    I --> |UDP Protocol| J[Forward to UDP_FORWARD_HOST:PORT]
    J --> |XML formatted traps| K[External Monitoring Systems]

    style A fill:#f9f,stroke:#333,stroke-width:2px
    style B fill:#bbf,stroke:#333,stroke-width:2px
    style G fill:#bfb,stroke:#333,stroke-width:2px
    style K fill:#fbb,stroke:#333,stroke-width:2px
```
*(Note: This diagram is based on the content of `project_documents/mermaid-diagram.txt`)*

## 2. Goals and Objectives

### 2.1. Primary Goal
To ensure the reliable, accurate, and timely forwarding of all processed SNMPv3 traps to both the designated Kafka topic and the specified UDP endpoint, thereby restoring and enhancing our network monitoring data pipeline.

### 2.2. Key Objectives
*   **Resolve Forwarding Errors:** Eliminate the UDP forwarding failures previously caused by incorrect time-based message formatting in Fluentd.
*   **Ensure Data Integrity:** Implement mechanisms (buffering, timeouts, retries) to minimize message loss and ensure data completeness during the forwarding process.
*   **Standardize Deployment:** Provide a stable, containerized solution (via `Dockerfile.fixed` and `docker-compose.yml.fixed`) for easy and repeatable deployments.
*   **Maintain Network Compatibility:** Ensure the solution operates seamlessly within the `mvp-setup_opensearch-net` Docker network, maintaining connectivity with Kafka and other dependent services.
*   **Improve Maintainability:** Structure the solution so that future configuration adjustments (e.g., to message formats or output parameters) are straightforward.

## 3. Target Audience & Stakeholders
This solution primarily serves the following stakeholders:
*   **Network Operations Team:** Relies on timely and accurate SNMP trap data for network monitoring, troubleshooting, and incident response.
*   **Data Engineering Team:** Manages the Kafka pipeline and ensures data availability for downstream analytics, reporting, and archival systems.
*   **DevOps/Platform Team:** Responsible for the deployment, maintenance, and operational stability of the containerized service.

## 4. Product Features (Functional Requirements)

### 4.1. FR1: SNMPv3 Trap Ingestion
The system MUST successfully ingest SNMPv3 traps received via the standard `snmptrapd` service.

### 4.2. FR2: Fluentd-based Processing
All ingested SNMPv3 traps MUST be processed by a Fluentd instance (version 1.16-1 or a compatible subsequent version). Processing includes parsing and any necessary transformations as defined in `fluent.conf.fixed`.

### 4.3. FR3: Dual Destination Forwarding
Processed trap data MUST be concurrently forwarded to the following two destinations:
    *   **Kafka:** A configurable Kafka topic within our existing Kafka cluster.
    *   **UDP Endpoint:** A configurable UDP endpoint, which defaults to `165.202.6.129:1237`.

### 4.4. FR4: Correct Message Formatting for UDP
Messages forwarded to the UDP endpoint MUST be correctly formatted to avoid errors. Specifically, the previous issue caused by the `%{time}` placeholder in the message structure MUST be resolved.

### 4.5. FR5: Containerized Deployment
The entire solution MUST be deployable as a Docker container named `fluentd-snmp-trap`.
    *   The Docker image MUST be built using `Dockerfile.fixed` from the `fluent/fluentd:v1.16-1` base image.
        *   Key build steps include: installing `net-snmp` and related tools; installing Fluentd plugins (`snmp`, `fluent-plugin-kafka`, `fluent-plugin-remote_syslog`, `fluent-plugin-record-modifier`, `fluent-plugin-udp`); and copying custom components (`fluentd-snmp/plugins/in_snmptrapd.rb`, `fluentd-snmp/conf/snmptrapd.conf`, `fluentd-snmp/entrypoint.sh`, `fluentd-snmp/trap-capture.sh`, and `fluent.conf.fixed`).
    *   The container's SNMP trap port `1162/udp` MUST be mapped from the host.
    *   SNMP MIB files MUST be made available to the container by mounting `./fluentd-snmp/mibs` to `/fluentd/mibs` (read-only).
    *   The container's behavior MUST be configurable via environment variables as defined in `docker-compose.yml.fixed`, including:
        *   SNMPv3 settings (`SNMPV3_USER`, `SNMPV3_AUTH_PASS`, `SNMPV3_PRIV_PASS`, etc.)
        *   Kafka target (`KAFKA_BROKER`, `KAFKA_TOPIC`)
        *   UDP forwarding details (`UDP_FORWARD_HOST`, `UDP_FORWARD_PORT`)
    *   Deployment SHOULD be manageable via the `docker-compose.yml.fixed` file (service name `fluentd-snmp-fixed`) or equivalent `docker run` commands.
    *   The container SHOULD use the custom `/entrypoint.sh` script and run as `root` to bind to the privileged SNMP port.
    *   A healthcheck MUST be configured to verify the `snmptrapd` process is running within the container.

### 4.6. FR6: Network Integration
The deployed Docker container MUST operate correctly within the `opensearch-net` Docker bridge network, as defined in `docker-compose.yml.fixed`. It MUST be able to establish and maintain connections to the `kafka:9092` service (its declared dependency) and any other specified network services for UDP forwarding.

## 5. Non-Functional Requirements (NFRs)

### 5.1. NFR1: Reliability & Data Integrity
*   The system MUST implement robust error handling for network connectivity issues or temporary unavailability of destination endpoints (Kafka, UDP).
*   Fluentd SHOULD be configured with appropriate memory buffering, retry mechanisms (e.g., exponential backoff), and configurable timeouts for its output plugins to prevent data loss.

### 5.2. NFR2: Maintainability
*   Core configurations (e.g., Fluentd processing rules, output plugin parameters, Kafka topic, UDP endpoint) SHOULD be managed through the `fluent.conf.fixed` file.
*   Updates to these configurations SHOULD be achievable by modifying the configuration file, rebuilding the Docker image, and redeploying the container.
*   Logging from the container (Fluentd, snmptrapd) MUST be sufficient to diagnose operational issues.

### 5.3. NFR3: Performance
The system MUST be capable of processing and forwarding the expected volume of SNMP traps from our production environment without introducing significant latency or message backlog. (Performance benchmarks from `load-test-pipeline.sh` can serve as a baseline).

### 5.4. NFR4: Security Considerations
*   As the system handles SNMPv3 traps, it MUST adhere to necessary security practices for managing SNMPv3 credentials and configurations if handled directly by components within its scope.
*   The Docker container SHOULD run with the least privileges necessary.
*   Dependencies, including the base Fluentd image and plugins, SHOULD be periodically reviewed for security vulnerabilities.

### 5.5. NFR5: Monitoring & Operability
*   The system (container) MUST provide adequate logging for operational monitoring (e.g., successful trap processing, forwarding attempts, errors).
*   Consideration SHOULD be given to exposing key operational metrics from Fluentd if feasible (e.g., queue length, error rates). (The `monitor-snmp-pipeline.sh` script indicates an existing need/practice).

## 6. Success Metrics
The success of this solution will be measured by:
*   **Error Rate:** Zero instances of UDP forwarding failures attributable to the previously identified time-formatting issue.
*   **Data Delivery Rate:** >99.9% of successfully ingested and processed SNMPv3 traps are delivered to both Kafka and the target UDP endpoint (allowing for configured retries and acceptable transient network disruptions).
*   **Operational Stability:** The containerized service operates reliably without crashes or unexplained service interruptions for extended periods (e.g., >30 days between interventions not related to planned maintenance).
*   **Deployment Verification:** Successful and repeatable deployment using the provided `Dockerfile.fixed` and `docker-compose.yml.fixed` as confirmed by the DevOps team.
*   **Stakeholder Confirmation:** Positive feedback from Network Operations and Data Engineering teams confirming that data is accurately and consistently available in their respective systems.

## 7. Release Criteria
The solution is considered ready for production release when the following criteria are met:
*   All Functional Requirements (FR1-FR6) are implemented and successfully verified through automated and manual testing (as per `test-fixed-container.sh` and direct UDP tests).
*   Critical Non-Functional Requirements (NFR1: Reliability, NFR2: Maintainability, NFR5: Monitoring) are met and validated.
*   The `deployment-steps.md` document is reviewed and confirmed to be accurate and complete for production deployment.
*   No critical or high-severity bugs related to the core forwarding functionality remain open.
*   Successful completion of a short-term stability test in a pre-production environment (e.g., 24-48 hours of error-free operation under representative load).

## 8. Future Considerations & Potential Roadmap
While the current scope addresses the immediate UDP forwarding issue, future enhancements could include:
*   **Enhanced Alerting:** Integration with a centralized alerting system for proactive notification of processing errors or pipeline failures.
*   **Dynamic Configuration:** Exploration of mechanisms for updating certain Fluentd configurations (e.g., filter rules, output parameters) without requiring a full container restart, if operationally beneficial and technically feasible.
*   **Expanded Output Options:** Support for additional output destinations or data formats based on evolving business needs.
*   **Advanced Metrics:** More granular performance and operational metrics exposed from Fluentd for richer monitoring dashboards.
*   **Schema Management:** For Kafka-bound data, integrate with a schema registry if not already in place. 