#!/bin/bash
# Script to restart the fluentd-snmp container after MIB file updates

echo "Restarting fluentd-snmp container to load the updated MIB files..."

# Get the container ID of the fluentd-snmp container
CONTAINER_ID=$(docker ps -q -f name=fluentd-snmp)

if [ -z "$CONTAINER_ID" ]; then
  echo "Error: fluentd-snmp container is not running."
  
  # Check if it exists but is stopped
  STOPPED_CONTAINER=$(docker ps -a -q -f name=fluentd-snmp)
  if [ -n "$STOPPED_CONTAINER" ]; then
    echo "Container exists but is stopped. Starting container..."
    docker start $STOPPED_CONTAINER
    echo "Container started. MIB files should be loaded automatically."
  else
    echo "Container doesn't exist. Please deploy the fluentd-snmp stack first."
  fi
else
  echo "Restarting container $CONTAINER_ID..."
  docker restart $CONTAINER_ID
  echo "Container restarted successfully. New MIB files should be loaded automatically."
  
  # Wait a moment for the container to start up
  sleep 2
  
  # Check logs to verify MIB loading
  echo "Checking container logs for MIB loading status:"
  docker logs --tail 10 $CONTAINER_ID
fi

echo "Done. SNMP trap handling with the new MIB files should now be operational." 