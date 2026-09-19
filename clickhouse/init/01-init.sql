CREATE DATABASE IF NOT EXISTS cdc_db;

CREATE TABLE IF NOT EXISTS cdc_db.customers
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

CREATE TABLE IF NOT EXISTS cdc_db.orders
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
CREATE VIEW IF NOT EXISTS cdc_db.customers_latest AS
SELECT * FROM cdc_db.customers FINAL WHERE NOT __deleted;

CREATE VIEW IF NOT EXISTS cdc_db.orders_latest AS
SELECT * FROM cdc_db.orders FINAL WHERE NOT __deleted;
