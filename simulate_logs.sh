#!/bin/bash

while true; do
  # Create a sample JSON log message.
  message=$(jq -n --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" --arg msg "Test log message for MVP" '{timestamp: $ts, message: $msg}')
  
  # Send the message to Fluentd on port 24224.
  echo "$message" | nc -w 1 127.0.0.1 24224
  
  echo "Sent log: $message"
  
  # Wait a short period before sending the next message.
  sleep 10
done
