#!/bin/bash
# test_mvp.sh
# This script sends a test log message to Fluentd and queries OpenSearch to verify ingestion.

# --- Configuration ---
# Set the OpenSearch credentials and host (adjust if needed)
OPENSEARCH_USER="admin"
OPENSEARCH_PASS="Str0ng!P@ssw0rd#2025"
OPENSEARCH_HOST="localhost"  # assuming opensearch-node1 is published on port 9200

# The topic/index to check (adjust based on your ML pipeline processing)
# For example, if your ML pipeline writes to an index named "logs" or "anomalies".
INDEX_TO_CHECK="logs"

# --- Step 1: Send a sample log message to Fluentd ---
echo "Sending test log message to Fluentd on port 24224..."
echo '{"timestamp": "2025-02-03T10:00:00Z", "message": "This is a test log for the MVP"}' | nc -w 1 127.0.0.1 24224

# --- Step 2: Wait for processing ---
echo "Waiting 15 seconds for the message to propagate..."
sleep 15

# --- Step 3: Query OpenSearch for the test log ---
echo "Querying OpenSearch index '${INDEX_TO_CHECK}' for the test log message..."
curl -u "${OPENSEARCH_USER}:${OPENSEARCH_PASS}" -X GET "http://${OPENSEARCH_HOST}:9200/${INDEX_TO_CHECK}/_search?pretty"

echo "Test complete."
