#!/bin/bash
# Monitoring script for SNMP pipeline

echo "=== SNMP Pipeline Monitoring ==="
echo "Press Ctrl+C to exit"
echo

# Function to display status
show_status() {
  clear
  echo "=== SNMP Pipeline Status ($(date)) ==="
  echo
  
  # Show container status
  echo "1. Container Status:"
  docker ps | grep fluentd-snmp-trap
  echo
  
  # Show buffer status
  echo "2. Buffer Status:"
  docker exec fluentd-snmp-trap ls -lah /fluentd/buffer/kafka /fluentd/buffer/error 2>/dev/null || echo "No buffer directories found"
  echo
  
  # Show last 5 traps
  echo "3. Last 5 SNMP Traps:"
  docker exec fluentd-snmp-trap tail -n 10 /var/log/snmptrapd.log 2>/dev/null | grep SNMPTRAP: | tail -n 5 || echo "No traps found"
  echo
  
  # Show Fluentd logs
  echo "4. Last 5 Fluentd Log Entries:"
  docker logs fluentd-snmp-trap 2>&1 | tail -n 5
  echo
  
  # Check for errors
  echo "5. Error Check:"
  if docker exec fluentd-snmp-trap ls -la /fluentd/log 2>/dev/null | grep -q "error_"; then
    echo "⚠️ Error logs found:"
    docker exec fluentd-snmp-trap ls -la /fluentd/log | grep "error_"
  else
    echo "✅ No error logs found."
  fi
  echo
  
  echo "Press Ctrl+C to exit, updating in 5s..."
}

# Loop to update status
while true; do
  show_status
  sleep 5
done 