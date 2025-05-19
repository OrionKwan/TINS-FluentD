# NM Server Setup Checklist for SNMPv3 Traps

Use this checklist to verify all required configurations for your NM server to successfully send SNMPv3 traps to the fluentd-snmp container.

## Pre-requisites

- [ ] Net-SNMP tools installed on NM server
- [ ] Network connectivity verified between NM server and container host
- [ ] Container's Engine ID discovered and documented
- [ ] Port 1162/UDP access confirmed between NM server and container host

## Engine ID Information

Document your Engine ID information here:

- Container's Engine ID: `_____________________`
- Engine ID format: `0x` followed by hexadecimal characters
- Engine ID discovery date: `__/__/____`

## SNMPv3 User Configuration

- [ ] SNMPv3 user created with the following parameters:
  - Username: `NCEadmin`
  - Authentication Protocol: `MD5`
  - Authentication Password: `P@ssw0rdauth`
  - Privacy Protocol: `AES`
  - Privacy Password: `P@ssw0rddata`
  - Engine ID: `[DISCOVERED_ENGINE_ID]`

## NM Server-Specific Configuration

Check the appropriate section for your NM server platform:

### HP OpenView/NNMi

- [ ] Updated snmpnotify.conf file with Engine ID
- [ ] Created proper user profile with auth/priv settings
- [ ] Verified SNMP trap target configuration to point to container's IP:1162
- [ ] Restarted trap forwarding service after configuration

### IBM Tivoli

- [ ] Updated /etc/snmp/snmptrap.conf with Engine ID
- [ ] Created proper user with authentication and privacy settings
- [ ] Configured trap destination to container's IP:1162
- [ ] Restarted trap sending service after configuration changes

### CA Spectrum

- [ ] Updated SNMPv3Configuration XML with correct Engine ID
- [ ] Set security name, auth protocol and password
- [ ] Set privacy protocol and password
- [ ] Configured trap destination to container's IP:1162
- [ ] Restarted SpectroSERVER service

### Other NM Platform: _____________________

- [ ] Located SNMP trap configuration file
- [ ] Added Engine ID to configuration
- [ ] Configured SNMPv3 user credentials
- [ ] Set trap destination to container's IP:1162
- [ ] Restarted relevant services

## Test Trap Configuration

- [ ] Created test trap template with the following:
  - OID: `1.3.6.1.6.3.1.1.5.1` (or platform-specific test OID)
  - At least one variable binding
  - Unique identifier in message for verification

## Verification Steps

- [ ] Command-line test successful before NM server test
  - [ ] Ran `test-with-correct-engine-id.sh` with success
- [ ] Generated test trap from NM server
- [ ] Verified trap reception in container:
  ```
  docker exec fluentd-snmp-trap tail -f /var/log/snmptrapd.log
  ```
- [ ] Verified UDP forwarding using tcpdump:
  ```
  tcpdump -i any -n port 1237
  ```
- [ ] Verified Kafka message delivery if applicable
  ```
  kafka-console-consumer --bootstrap-server [KAFKA_SERVER]:9092 --topic [TOPIC_NAME]
  ```

## Notes and Issues

Document any platform-specific notes or issues encountered during setup:

```
[NOTES AREA]
```

## Contact Information

- SI Technical Contact: _____________________
- Container Support Contact: _____________________
- Date of Integration: __/__/____

## Verification Signatures

- SI Engineer: _____________________
- Container Support Engineer: _____________________ 