#!/bin/bash
export OPENSEARCH_INITIAL_ADMIN_PASSWORD="Admin123!"
docker compose down
docker compose up -d --build 