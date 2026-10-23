#!/bin/bash
# Creates the destination tables and views in $CLICKHOUSE_DB (the image itself
# creates the database). A shell script rather than plain .sql so the database
# name comes from .env instead of being hardcoded.
set -eu

clickhouse-client --multiquery --port "${NATIVE_PORT:-9000}" \
  -u "${CLICKHOUSE_USER}" --password "${CLICKHOUSE_PASSWORD}" -d "${CLICKHOUSE_DB}" <<'SQL'
CREATE TABLE IF NOT EXISTS customers
(
    id         Int32,
    full_name  String,
    email      String,
    created_at DateTime64(3),
    updated_at DateTime64(3),
    __op       String,
    __ts_ms    DateTime64(3),
    __deleted  Bool
)
ENGINE = ReplacingMergeTree(__ts_ms)
ORDER BY id;

CREATE TABLE IF NOT EXISTS orders
(
    id          Int32,
    customer_id Int32,
    amount      Decimal(10, 2),
    status      String,
    created_at  DateTime64(3),
    updated_at  DateTime64(3),
    __op        String,
    __ts_ms     DateTime64(3),
    __deleted   Bool
)
ENGINE = ReplacingMergeTree(__ts_ms)
ORDER BY id;

-- FINAL forces the dedup pass at query time so reads are correct immediately,
-- not only after a background merge, and filters out soft-deleted rows.
CREATE VIEW IF NOT EXISTS customers_latest AS
SELECT * FROM customers FINAL WHERE NOT __deleted;

CREATE VIEW IF NOT EXISTS orders_latest AS
SELECT * FROM orders FINAL WHERE NOT __deleted;
SQL
