#!/bin/sh
# Simple script to capture SNMP traps and write them to a log file with timestamps

# Log file location - this is what Fluentd will monitor
TRAP_LOG="/var/log/snmptrapd.log"

# Ensure the log file exists and has proper permissions
touch $TRAP_LOG
chmod 666 $TRAP_LOG

# Clear the log file to start fresh
echo "SNMPTRAP: $(date '+%Y-%m-%d %H:%M:%S') Trap listener initialized" > $TRAP_LOG

# This function processes each line of input and formats it for logging
process_line() {
  while read line; do
    if [ -n "$line" ] && ! echo "$line" | grep -q "NET-SNMP version"; then
      echo "SNMPTRAP: $(date '+%Y-%m-%d %H:%M:%S') $line" >> $TRAP_LOG
    fi
  done
}

# Start snmptrapd in foreground mode and pipe its output to our processing function
echo "Starting SNMP trap capture to $TRAP_LOG"
/usr/sbin/snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf 0.0.0.0:1162 | process_line
