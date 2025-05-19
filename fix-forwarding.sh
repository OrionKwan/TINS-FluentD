#!/bin/bash
# Script to fix Fluentd forwarding issues

# Stop the container 
echo "Stopping fluentd-snmp-trap container..."
docker stop fluentd-snmp-trap

# Create updated configuration
cat > simpler-fluent.conf << EOF
# Read SNMP trap log file
<source>
  @type tail
  path /var/log/snmptrapd.log
  tag snmp.trap
  pos_file /tmp/snmptrapd.pos
  read_from_head true
  
  <parse>
    @type none
  </parse>
</source>

# Output configuration
<match snmp.trap>
  @type copy
  
  # Output to Kafka
  <store>
    @type kafka2
    brokers "kafka:9092"
    topic "snmp_traps"
    
    <format>
      @type json
    </format>
  </store>
  
  # Output to UDP directly
  <store>
    @type udp
    host "165.202.6.129"
    port 1237
    message_format "<snmp_trap><timestamp>%{time}</timestamp><version>SNMPv3</version><data>%{message}</data></snmp_trap>"
  </store>
  
  # Debug output
  <store>
    @type stdout
  </store>
</match>

<system>
  log_level info
</system>
EOF

# Modify the Docker Compose file to update the volume mapping
echo "Creating new Docker Compose file with updated configuration..."
sed 's/- \.\/fluentd-snmp\/conf:\/fluentd\/etc:ro/- \.\/fluentd-snmp\/conf:\/fluentd\/etc/' docker-compose.yml > docker-compose-updated.yml

# Copy the new configuration file to the host's conf directory
echo "Copying new configuration file..."
mkdir -p fluentd-snmp/conf
cp simpler-fluent.conf fluentd-snmp/conf/fluent.conf

# Start just the fluentd-snmp container with the updated configuration
echo "Starting the container with updated configuration..."
docker-compose -f docker-compose-updated.yml up -d fluentd-snmp

echo "Installation of UDP plugin..."
sleep 5
docker exec fluentd-snmp-trap gem install fluent-plugin-udp

echo "Restarting the container..."
docker restart fluentd-snmp-trap

# Verify the container is running
echo "Verifying container status..."
docker ps | grep fluentd-snmp-trap

echo "Done! The container should now forward to both Kafka and UDP." 