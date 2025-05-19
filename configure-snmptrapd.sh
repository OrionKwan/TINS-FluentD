#!/bin/bash

# Script to configure snmptrapd to listen on the macvlan interface
CONTAINER_NAME="fluentd-snmp-trap"

echo "Configuring snmptrapd in $CONTAINER_NAME container..."

# Give the container time to start
sleep 5

# Get the current container status
CONTAINER_RUNNING=$(docker ps -q -f name=$CONTAINER_NAME)

if [ -z "$CONTAINER_RUNNING" ]; then
  echo "Container $CONTAINER_NAME is not running!"
  exit 1
fi

echo "Restarting snmptrapd to listen on 192.168.8.100:1162..."

# Restart snmptrapd to listen on the macvlan interface
docker exec $CONTAINER_NAME sh -c "pkill snmptrapd && \
  /usr/sbin/snmptrapd -Lf /var/log/snmptrapd.log -c /etc/snmp/snmptrapd.conf -f -Lo -A -n 192.168.8.100 1162 &"

# Check if the daemon is running correctly
SNMPTRAPD_COUNT=$(docker exec $CONTAINER_NAME sh -c "ps aux | grep -v grep | grep '192.168.8.100 1162' | wc -l")

if [ "$SNMPTRAPD_COUNT" -gt 0 ]; then
  echo "snmptrapd is now listening on 192.168.8.100:1162"
  exit 0
else
  echo "Failed to configure snmptrapd!"
  exit 1
fi 