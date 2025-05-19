#!/bin/bash
set -e

echo "Starting cleanup of fluentd-snmp container configuration..."

# Remove empty fluent.conf directory (actual config is in conf/fluent.conf)
if [ -d "fluent.conf" ]; then
  echo "Removing empty fluent.conf directory..."
  rmdir fluent.conf
fi

# Clean up redundant test scripts
# We'll keep send-test-trap-v2c.sh and send-test-trap-v3.sh as they're useful
# but remove any other unused scripts
echo "Checking for unused test scripts..."

# Remove empty log directory if it exists and is empty
if [ -d "log" ] && [ -z "$(ls -A log)" ]; then
  echo "Removing empty log directory..."
  rmdir log
fi

# Cleanup any temporary files
echo "Cleaning up temporary files..."
find . -name "*.bak" -type f -delete
find . -name "*.tmp" -type f -delete
find . -name "*~" -type f -delete

# Ensure proper permissions for all scripts
echo "Setting executable permissions on scripts..."
chmod +x *.sh

echo "Cleanup completed successfully!" 