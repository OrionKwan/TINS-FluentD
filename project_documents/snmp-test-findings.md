# SNMP Trap Testing Findings

## Summary

We performed extensive testing of the SNMPv3 trap handling capability with a focus on Engine ID configuration. The testing revealed several important insights about the system's behavior and configuration.

## Key Findings

1. **Correct Engine ID Identified**: 
   - The correct Engine ID of the system is `0x80001F88807C0F9A615F4B0768000000`
   - This was confirmed in the SNMPv3 user configuration file `/var/lib/net-snmp/snmptrapd.conf`
   - It is also set as an environment variable `SNMPV3_ENGINE_ID` in the container

2. **SNMPv3 Authentication Protocol**:
   - The system is configured to use **MD5** for authentication, not SHA
   - SNMPv3 traps with SHA authentication were not recognized
   - SNMPv3 traps with MD5 authentication were successfully received

3. **Trap Processing Pipeline**:
   - SNMP traps are successfully received by snmptrapd
   - Traps are processed by Fluentd and put into the proper format
   - Logs confirm the trap processing is working correctly

4. **Test Results**:
   - SNMPv2c traps: ✅ Successfully received and processed
   - SNMPv3 traps with correct Engine ID and MD5 auth: ✅ Successfully received
   - SNMPv3 traps with correct Engine ID but SHA auth: ❌ Failed (expected due to config)
   - SNMPv3 traps with incorrect Engine ID: ❌ Failed (expected behavior)
   - Auto-discovery mode (without specifying Engine ID): ❌ Not supported

## Configuration Details

The SNMPv3 configuration in the container uses:

```
createUser -e 0x80001F88807C0F9A615F4B0768000000 NCEadmin MD5 P@ssw0rdauth AES P@ssw0rddata
```

Key configuration parameters:
- **Engine ID**: `0x80001F88807C0F9A615F4B0768000000`
- **Username**: `NCEadmin`
- **Auth Protocol**: `MD5`
- **Auth Password**: `P@ssw0rdauth`
- **Privacy Protocol**: `AES`
- **Privacy Password**: `P@ssw0rddata`

## Recommendations

1. **Update Client Configuration**:
   - All SNMPv3 clients (trap senders) must use the Engine ID `0x80001F88807C0F9A615F4B0768000000`
   - Clients must use MD5 authentication, not SHA
   - Use the correct username and passwords

2. **Script Improvement**:
   - The test script has been updated to detect the correct Engine ID automatically
   - It now tries both MD5 and SHA authentication methods
   - Better error reporting and diagnostics have been added

3. **Documentation Update**:
   - Update documentation to clearly specify the Engine ID requirement
   - Make it clear that MD5 authentication is required, not SHA
   - Include sample command for sending valid traps

## Sample Working Command

To send a valid SNMPv3 trap that will be properly received and processed:

```bash
snmptrap -v 3 -e 0x80001F88807C0F9A615F4B0768000000 -u NCEadmin -a MD5 -A P@ssw0rdauth -x AES -X P@ssw0rddata \
  -l authPriv localhost:1162 '' \
  1.3.6.1.6.3.1.1.5.1 1.3.6.1.2.1.1.3.0 s "Test Trap Message"
```

## Testing Output

Our testing confirmed that:

1. Traps with the correct Engine ID and authentication are properly received:
   ```
   SNMPTRAP: 2025-04-25 00:43:09 DISMAN-EVENT-MIB::sysUpTimeInstance "ENGINE-ID-TEST-1745541777-CORRECT-MD5"
   FORMATTED: <trap><timestamp>2025-04-25 00:43:09</timestamp><data>DISMAN-EVENT-MIB::sysUpTimeInstance "ENGINE-ID-TEST-1745541777-CORRECT-MD5"</data></trap>
   ```

2. Fluentd correctly processes the traps:
   ```
   2025-04-25 00:43:20.870441231 +0000 snmp.trap: {"message":"2025-04-25 00:43:20 DISMAN-EVENT-MIB::sysUpTimeInstance \"ENGINE-ID-TEST-1745541777-V2C\""}
   ```

3. The end-to-end pipeline is functioning correctly, with traps being forwarded to their destinations.

## Conclusion

The SNMPv3 trap configuration is working correctly when using the exact Engine ID, username, and authentication parameters. The main source of potential issues would be mismatches in these parameters. With the correct configuration, SNMPv3 traps are reliably received and processed by the system. 