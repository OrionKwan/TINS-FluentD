#!/bin/bash
# Direct script to modify Fluentd's configuration within the container

# Create a temporary configuration file
cat > temp-fluent.conf << 'EOF'
# SNMP trap log input
<source>
  @type tail
  path /var/log/snmptrapd.log
  tag snmp.trap
  pos_file /tmp/snmptrapd.pos
  read_from_head true
  
  <parse>
    @type regexp
    expression /^(SNMPTRAP: |FORMATTED: )(?<message>.*)/
  </parse>
</source>

# Forward to both Kafka and UDP
<match snmp.trap>
  @type copy
  
  # Send to stdout for debugging
  <store>
    @type stdout
  </store>
  
  # Forward to UDP destination
  <store>
    @type exec
    command echo "<snmp_trap><timestamp>$(date)</timestamp><version>SNMPv3</version><data>%{message}</data></snmp_trap>" | nc -u 165.202.6.129 1237
    <format>
      @type tsv
      keys message
    </format>
    <inject>
      tag_key tag
      time_key time
      time_format %Y-%m-%dT%H:%M:%S%z
    </inject>
  </store>
</match>
EOF

# Stop container
echo "Stopping fluentd-snmp-trap container..."
docker stop fluentd-snmp-trap

echo "Updating configuration from outside..."
docker cp temp-fluent.conf fluentd-snmp-trap:/fluentd/etc/fluent.conf.new

echo "Starting container..."
docker start fluentd-snmp-trap

echo "Applying configuration from inside..."
docker exec fluentd-snmp-trap sh -c "cat /fluentd/etc/fluent.conf.new > /fluentd/etc/fluent.conf"

echo "Restarting fluentd process..."
docker exec fluentd-snmp-trap sh -c "pkill -f fluentd && fluentd -c /fluentd/etc/fluent.conf &"

echo "Configuration updated and service restarted." 