#!/bin/sh
# Continuously inserts one random order every N seconds, so the CDC pipeline
# (Debezium -> Kafka -> ClickHouse) has a steady stream of changes to show off.
# customer_id is picked at random from existing rows in `customers`.
set -eu

POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-cdc_db}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-10}"

echo "Generating one random order every ${INTERVAL_SECONDS}s into ${POSTGRES_DB}.orders (Ctrl+C to stop) ..."

while true; do
  docker exec "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "
    INSERT INTO public.orders (customer_id, amount, status, created_at, updated_at)
    SELECT (SELECT id FROM public.customers ORDER BY random() LIMIT 1),
           round((random() * 490 + 10)::numeric, 2),
           (ARRAY['pending','shipped','completed','cancelled'])[floor(random() * 4 + 1)],
           now(),
           now()
    RETURNING id, customer_id, amount, status, created_at;
  "
  sleep "${INTERVAL_SECONDS}"
done
