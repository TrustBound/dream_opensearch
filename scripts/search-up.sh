#!/bin/sh
# Starts the OpenSearch of docker-compose.yml for the tests, and waits until
# each node is healthy. "make search-up" runs this script.
set -eu

# Start the secured node first, with no wait, so both nodes start at the
# same time. Then wait until each one is healthy.
docker compose up -d opensearch-secured
docker compose up -d --wait opensearch
docker compose up -d --wait opensearch-secured
