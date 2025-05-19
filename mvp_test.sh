#!/bin/bash
set -euo pipefail

# ===========================================
# MVP End-to-End Test Case for Telecom OT System
# ===========================================
#
# This script simulates the ingestion of log messages into Fluentd,
# waits for the ML pipeline to process them, and then queries OpenSearch
# to verify that logs and/or anomalies have been indexed.
#
# Requirements:
# - curl, jq, and nc (netcat) must be installed on your host.
# - OpenSearch should be accessible at the host URL below.
#
# Adjust variables as needed.

# Variables (adjust as needed)
OPENSEARCH_URL="http://localhost:9200"
ADMIN_USER="admin"
ADMIN_PASS="Str0ng!P@ssw0rd#2025"
FLUENTD_HOST="127.0.0.1"
FLUENTD_PORT="24224"
NORMAL_LOG='{"timestamp": "2025-02-03T10:00:00Z", "message": "normal log message", "severity": "info"}'
ANOMALY_LOG='{"timestamp": "2025-02-03T10:00:05Z", "message": "ERROR: anomaly detected in system X", "severity": "error"}'

echo "=========================="
echo "Step 1: Waiting for OpenSearch to be healthy"
echo "=========================="

# Wait until OpenSearch's _cluster/health endpoint returns a valid status.
max_retries=30
for (( i=1; i<=max_retries; i++ )); do
  health=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "${OPENSEARCH_URL}/_cluster/health" || echo "{}")
  status=$(echo "$health" | jq -r '.status' || echo "null")
  if [ "$status" != "null" ] && [ "$status" != "" ]; then
    echo "OpenSearch is healthy (status: $status)"
    break
  fi
  echo "Attempt $i/$max_retries: OpenSearch not ready yet. Retrying in 5 seconds..."
  sleep 5
done

# ===========================================
echo "Step 2: Sending test log messages via Fluentd"
echo "=========================="

echo "Sending normal log message..."
echo "$NORMAL_LOG" | nc -u "$FLUENTD_HOST" "$FLUENTD_PORT"

echo "Sending anomalous log message..."
echo "$ANOMALY_LOG" | nc -u "$FLUENTD_HOST" "$FLUENTD_PORT"

# ===========================================
echo "Step 3: Waiting for ML Pipeline to process messages"
echo "=========================="
# Wait long enough for your ML pipeline to process the incoming logs
sleep 60

# ===========================================
echo "Step 4: Querying OpenSearch for indexed data"
echo "=========================="
# Replace "anomalies" with the actual index name used by your ML pipeline (if different)
curl -u "${ADMIN_USER}:${ADMIN_PASS}" "${OPENSEARCH_URL}/anomalies/_search?pretty" || echo "No anomalies index found"

echo "Test case completed."
