#!/bin/sh
# Registers the Debezium source and ClickHouse JDBC sink connectors against a
# running Kafka Connect worker. Safe to re-run: an existing connector with the
# same name is deleted and recreated from the current JSON file.
set -eu

CONNECT_URL="${CONNECT_URL:-http://connect:8083}"
CONNECTORS_DIR="${CONNECTORS_DIR:-/connectors}"

echo "Waiting for Kafka Connect at ${CONNECT_URL} ..."
until curl -sf "${CONNECT_URL}/connectors" > /dev/null 2>&1; do
  sleep 2
done
echo "Kafka Connect is up."

# source before sink: harmless either way, but keeps registration order predictable.
for dir in source sink; do
  for file in "${CONNECTORS_DIR}/${dir}"/*.json; do
    name=$(basename "${file}" .json)

    # Drop any previous instance so re-runs pick up config changes.
    curl -s -o /dev/null -X DELETE "${CONNECT_URL}/connectors/${name}" || true

    echo "Registering connector '${name}' from ${file} ..."
    http_status=$(curl -s -o /tmp/register-response.json -w "%{http_code}" \
      -X POST "${CONNECT_URL}/connectors" \
      -H "Content-Type: application/json" \
      -d @"${file}")

    if [ "${http_status}" != "200" ] && [ "${http_status}" != "201" ]; then
      echo "Failed to register ${name} (HTTP ${http_status}):"
      cat /tmp/register-response.json
      exit 1
    fi
    echo "  -> OK (HTTP ${http_status})"
  done
done

echo "All connectors registered."
