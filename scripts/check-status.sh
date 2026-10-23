#!/bin/sh
# Quick health/status snapshot for every connector in the cluster.
set -eu

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"

curl -sf "${CONNECT_URL}/connectors?expand=status"
echo
