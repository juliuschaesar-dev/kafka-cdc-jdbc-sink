#!/bin/sh
# Registers the Debezium source and ClickHouse JDBC sink connectors against a
# running Kafka Connect worker. Safe to re-run: an existing connector with the
# same name is deleted and recreated from the current JSON file.
set -eu

CONNECT_URL="${CONNECT_URL:-http://connect:8083}"
CONNECTORS_DIR="${CONNECTORS_DIR:-/connectors}"

response_file=$(mktemp)
trap 'rm -f "${response_file}"' EXIT

echo "Waiting for Kafka Connect at ${CONNECT_URL} ..."
until curl -sf "${CONNECT_URL}/connectors" > /dev/null 2>&1; do
  sleep 2
done
echo "Kafka Connect is up."

# Source is registered before sink so the sink's topics already exist or are about to be created.
for dir in source sink; do
  for file in "${CONNECTORS_DIR}/${dir}"/*.json; do
    name=$(basename "${file}" .json)

    # Drop any previous instance so re-runs pick up config changes (404 = nothing to drop).
    http_status=$(curl -s -o "${response_file}" -w "%{http_code}" -X DELETE "${CONNECT_URL}/connectors/${name}")
    if [ "${http_status}" != "204" ] && [ "${http_status}" != "404" ]; then
      echo "Failed to delete existing ${name} (HTTP ${http_status}):"
      cat "${response_file}"
      exit 1
    fi

    echo "Registering connector '${name}' from ${file} ..."
    http_status=$(curl -s -o "${response_file}" -w "%{http_code}" \
      -X POST "${CONNECT_URL}/connectors" \
      -H "Content-Type: application/json" \
      -d @"${file}")

    if [ "${http_status}" != "200" ] && [ "${http_status}" != "201" ]; then
      echo "Failed to register ${name} (HTTP ${http_status}):"
      cat "${response_file}"
      exit 1
    fi
    echo "  -> OK (HTTP ${http_status})"
  done
done

echo "All connectors registered."
