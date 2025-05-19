# TINS-FluentD

## SNMPv3 Engine ID Monitoring Tools

This package contains scripts to monitor and test SNMPv3 trap engine IDs.

## Prerequisites

- Net-SNMP utilities (net-snmp-utils) must be installed
- Basic bash environment
- Root or sudo access may be required to bind to ports below 1024

## Scripts

### 1. Engine ID Monitor (`snmp-engine-id-monitor.sh`)

This script listens for incoming SNMPv3 traps and extracts their Engine IDs in real-time.

**Usage:**
```bash
chmod +x snmp-engine-id-monitor.sh
./snmp-engine-id-monitor.sh
```

The script will:
- Start an SNMP trap listener on port 1162 (configurable in the script)
- Capture and display the Engine ID of any incoming SNMPv3 traps
- Continue running until terminated with Ctrl+C

### 2. Test Generator (`test-engine-id-monitor.sh`)

This script sends test SNMPv3 traps with various Engine IDs to test the monitoring script.

**Usage:**
```bash
chmod +x test-engine-id-monitor.sh
./test-engine-id-monitor.sh
```

The script will send multiple test traps with different Engine IDs to localhost:1162.

## Workflow

1. Run the monitor script in one terminal:
   ```bash
   ./snmp-engine-id-monitor.sh
   ```

2. Run the test generator in another terminal:
   ```bash
   ./test-engine-id-monitor.sh
   ```

3. Observer the monitor terminal to see the Engine IDs of the incoming traps.

## Customization

- Edit the `TRAP_PORT` variable in `snmp-engine-id-monitor.sh` to change the listening port
- Modify the Engine IDs array in `test-engine-id-monitor.sh` to test different Engine ID formats
- Adjust authentication parameters in both scripts if needed for your environment

## Troubleshooting

If no traps are being received:
1. Ensure no other process is using port 1162
2. Check for firewall rules blocking UDP on port 1162
3. Verify that the sender and receiver Engine IDs and authentication parameters match
4. Run the monitor with root/sudo if binding to the port requires elevated privileges 

## New Scripts

### 3. Extract Engine ID (`extract-engine-id.sh`)

This script captures network packets on port 1162 and extracts engine IDs from raw packet data.

**Usage:**
```bash
sudo ./extract-engine-id.sh
```

The script will:
- Capture UDP packets on port 1162
- Parse the hex dump to locate and extract engine IDs
- Display source IP and protocol information for context
- Doesn't rely on any existing snmptrapd process 

### 4. Monitor Existing snmptrapd (`monitor-existing-snmptrapd.sh`)

This script monitors the existing snmptrapd process and its log files to extract engine IDs without trying to start a new daemon.

**Usage:**
```bash
sudo ./monitor-existing-snmptrapd.sh
```

The script will:
- Detect the currently running snmptrapd
- Identify which port it's listening on
- Monitor log files for changes
- Parse log entries to extract engine IDs
- Uses multiple pattern matching approaches to find engine IDs in various formats
