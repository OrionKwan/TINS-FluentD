#!/bin/bash
# Script to check SNMP trap reception and processing

set -e

# Optional search term
SEARCH_TERM="$1"
SEARCH_OPTION=""
if [ -n "$SEARCH_TERM" ]; then
  SEARCH_OPTION="| grep -i '$SEARCH_TERM'"
fi

echo "======================================================================"
echo "🔍 SNMP Trap Reception Check"
echo "======================================================================"

# Check if container is running
if ! docker ps | grep -q fluentd-snmp-trap; then
  echo "❌ ERROR: fluentd-snmp container is not running!"
  exit 1
fi

# Check trap log
echo "📑 Last 10 trap log entries:"
eval "docker exec fluentd-snmp-trap cat /var/log/snmptrapd.log | tail -n 10 $SEARCH_OPTION"
echo ""

# Check Fluentd output
echo "📊 Last 10 Fluentd log entries:"
eval "docker logs fluentd-snmp-trap | tail -n 10 $SEARCH_OPTION"
echo ""

# Check Kafka
echo "📈 Kafka messages (last 5):"
if docker ps | grep -q kafka; then
  eval "docker exec kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic snmp_traps --from-beginning --max-messages 5 $SEARCH_OPTION"
else
  echo "⚠️ Kafka container not running"
fi
echo ""

# UDP Forwarding info
echo "📡 UDP Forwarding Information:"
echo "Your web application should receive the formatted XML data via UDP on port ${UDP_FORWARD_PORT:-5140}"
echo "To check UDP reception, run: nc -lu ${UDP_FORWARD_PORT:-5140} on host ${UDP_FORWARD_HOST:-192.168.8.30}"
echo ""

echo "======================================================================"
echo "✅ Check complete"
echo "======================================================================" 