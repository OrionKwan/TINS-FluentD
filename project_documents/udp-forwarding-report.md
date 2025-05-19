# UDP Forwarding Report

## Issue
The SNMPv3 traps are being received by the Fluentd container but not being successfully forwarded to the destination UDP server (165.202.6.129:1237).

## Tests Performed

1. **Direct UDP Testing**
   - Successfully sent UDP messages directly from host to destination (165.202.6.129:1237)
   - Successfully sent UDP messages from container using netcat
   - Successfully sent UDP messages using Ruby UDP Socket (same method used by Fluentd internally)

2. **Container Configuration**
   - Verified that container can communicate with the destination
   - Verified that Fluentd is running and processing SNMP traps
   - Verified Kafka output is working correctly

3. **Fluentd Configuration Analysis**
   - Found issues with the Fluentd UDP output configuration
   - Identified error in buffer configuration: `<buffer ...> argument includes 'time', but timekey is not configured`
   - Attempted to fix by adding timekey parameter but faced issues with container volume being read-only

## Core Issue Identified

The core issue is with the Fluentd UDP output plugin configuration. The error `<buffer ...> argument includes 'time', but timekey is not configured` is occurring because:

1. The message format includes `%{time}` which triggers Fluentd to use time-based buffering
2. When using time in format strings, Fluentd requires a timekey parameter in the buffer configuration
3. The container volume appears to be mounted read-only, preventing direct changes to the configuration

## Solution and Recommendations

1. **Short-term workaround**: Use direct UDP messaging to forward SNMP traps
   - The `test-udp-direct.sh` script demonstrates that UDP messaging to the destination works correctly
   - This can be used as a temporary solution

2. **Fix Fluentd configuration**:
   - Update the Fluentd container configuration with these changes:
     ```xml
     <store>
       @type udp
       @id out_udp
       host "#{ENV['UDP_FORWARD_HOST'] || '165.202.6.129'}"
       port "#{ENV['UDP_FORWARD_PORT'] || '1237'}"
       message_format <snmp_trap><version>SNMPv3</version><data>%{message}</data></snmp_trap>
       socket_buffer_size 16777216
       send_timeout 10
       ignore_error true
     </store>
     ```
   - Note: By removing `%{time}` from the message_format, we avoid the timekey error

3. **Rebuild container with fixed configuration**:
   - Create a new Dockerfile that includes the correct configuration
   - Rebuild and deploy the container with the fixed configuration

## Detailed Investigation Steps

1. Attempted to modify the fluent.conf file to fix the buffer configuration
2. Found the volume was mounted read-only, preventing direct changes
3. Tested direct UDP messaging to confirm network connectivity is working
4. Verified that the UDP plugin requires special configuration when using time in the message format
5. Created test scripts to verify different aspects of UDP communication

## Conclusion

The UDP forwarding issue is not a network connectivity or permission problem, but rather a configuration issue with the Fluentd UDP output plugin. The time formatting in the message triggers a requirement for timekey configuration in the buffer section.

Since the container volume is read-only, the solution requires rebuilding the container with the correct configuration. For immediate testing, direct UDP messaging can be used to verify that the destination can receive the messages correctly. 