import socket
import time

def wait_for_kafka(host, port, timeout=5):
    """Wait until a TCP connection to Kafka is successful."""
    while True:
        try:
            with socket.create_connection((host, port), timeout):
                print(f"Kafka is available at {host}:{port}")
                return
        except Exception as e:
            print(f"Waiting for Kafka at {host}:{port}... ({e})")
            time.sleep(5)

# Use the environment variable for Kafka broker if needed.
import os
KAFKA_BROKER = os.environ.get("KAFKA_BROKER", "kafka:9092")
kafka_host, kafka_port = KAFKA_BROKER.split(":")
kafka_port = int(kafka_port)

# Wait for Kafka to become available.
wait_for_kafka(kafka_host, kafka_port)

# Now proceed with creating the KafkaConsumer.
from kafka import KafkaConsumer
import json

TOPIC = "logs"

consumer = KafkaConsumer(
    TOPIC,
    bootstrap_servers=[KAFKA_BROKER],
    value_deserializer=lambda m: json.loads(m.decode('utf-8')),
    auto_offset_reset='earliest',
    enable_auto_commit=True
)

# Initialize OpenSearch (rest of your code remains the same)
from opensearchpy import OpenSearch
OPENSEARCH_HOST = os.environ.get("OPENSEARCH_HOST", "opensearch")
opensearch_client = OpenSearch(
    hosts=[{'host': OPENSEARCH_HOST, 'port': 9200}],
    http_compress=True
)

def detect_anomaly(log):
    message = log.get("message", "").lower()
    return "error" in message

print("Starting ML pipeline...")

while True:
    for message in consumer:
        log_data = message.value
        if detect_anomaly(log_data):
            anomaly = {
                "timestamp": log_data.get("timestamp", time.time()),
                "message": log_data.get("message"),
                "anomaly": True
            }
            response = opensearch_client.index(index="anomalies", body=anomaly)
            print("Anomaly detected and indexed:", response)
    time.sleep(1)
