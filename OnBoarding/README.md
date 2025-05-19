# Network OnBoarding Process

This directory contains tools and scripts for the network onboarding process.

## Step 1: Test Trap Capturing

The first step in the onboarding process is to capture SNMP trap traffic on port 1162 for testing and verification purposes.

### How to Use the Capture Tool

1. Ensure you have `sudo` privileges to run `tcpdump`
2. Run the capture script:

```bash
# Basic usage (captures for 60 seconds)
./capture_snmp_traps.sh

# Capture for a specific duration (e.g., 5 minutes)
./capture_snmp_traps.sh 300

# Capture with a custom output filename
./capture_snmp_traps.sh 60 my_custom_capture.pcap
```

The script will:
- Capture SNMP trap traffic on port 1162 on the ens160 interface
- Save the captured packets as a .pcap file in the "1. Test Trap Capturing" folder
- Display information about the captured file

### Analyzing Captured Traffic

You can analyze the captured .pcap files using Wireshark or other packet analysis tools.

```bash
# Open the captured file in Wireshark
wireshark "/path/to/captured/file.pcap"
```

## Next Steps

After capturing and verifying SNMP trap traffic, proceed to the next onboarding steps as required. 