#!/bin/bash

# Simple UDP server to listen for traps on port 1237
echo "Starting UDP listener on port 1237..."
nc -ul 1237 > udp_received.log &
NC_PID=$!

echo "UDP listener started with PID $NC_PID"
echo "Press CTRL+C to stop capturing"

# Wait for user to press CTRL+C
trap "kill $NC_PID; echo 'UDP listener stopped'; exit 0" INT
while true; do
  sleep 1
  if [[ -s udp_received.log ]]; then
    echo "New UDP data received:"
    cat udp_received.log
    > udp_received.log  # Clear the file
  fi
done 