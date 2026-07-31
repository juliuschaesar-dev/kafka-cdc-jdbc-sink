#!/bin/sh
# Quick health/status snapshot for every connector in the cluster.
set -eu

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"

for name in $(curl -s "${CONNECT_URL}/connectors" | tr -d '[]"' | tr ',' '\n'); do
  [ -z "$name" ] && continue
  echo "== ${name} =="
  curl -s "${CONNECT_URL}/connectors/${name}/status"
  echo
  echo
done
