# Kafka CDC JDBC Sink

Real-time change data capture from **PostgreSQL** to **ClickHouse**, streamed through **Kafka** using **Debezium** for CDC and the **Confluent JDBC Sink connector** for delivery. Messages are Avro-encoded via **Schema Registry** to keep them small. **AKHQ** provides a UI for monitoring topics and connectors.

## Architecture

```
PostgreSQL --(Debezium CDC)--> Kafka --(JDBC Sink Connector)--> ClickHouse
                                  ^  ^
                                  |  |
                     Schema Registry  AKHQ (monitoring)
```

| Component            | Role                                                        | Image                                    |
|-----------------------|-------------------------------------------------------------|-------------------------------------------|
| PostgreSQL            | Source database (logical replication enabled)               | `postgres:16`                              |
| Kafka                 | Event streaming backbone (KRaft mode, no Zookeeper)           | `confluentinc/cp-kafka:7.6.1`              |
| Schema Registry       | Stores Avro schemas for topic keys/values                    | `confluentinc/cp-schema-registry:7.6.1`    |
| Kafka Connect         | Runs the Debezium source + JDBC sink connectors              | custom build, see [connect/Dockerfile](connect/Dockerfile) |
| ClickHouse            | Destination OLAP database                                    | `clickhouse/clickhouse-server:24.3`        |
| AKHQ                  | Web UI for Kafka topics, consumer groups, and connectors      | `tchiotludo/akhq:0.24.0`                   |

Two demo tables are replicated end-to-end: `public.customers` and `public.orders`.

## Prerequisites

- Docker and Docker Compose v2
- Ports `5432`, `8080`, `8081`, `8083`, `8123`, `9000`, `9092` free on the host

## Configuration

All ports, credentials, and database names live in `.env` (loaded automatically by Docker Compose):

```sh
cp .env.example .env
```

The `connect` container also forwards the Postgres/ClickHouse values from `.env` into its own
environment, and the Debezium/JDBC sink connector configs in [connectors/](connectors/) pull
them from there via Kafka Connect's built-in `EnvVarConfigProvider` (`${env:POSTGRES_PASSWORD}`,
`${env:CLICKHOUSE_PASSWORD}`, etc.) — no secrets are hardcoded in the connector JSON.

If you change `CLICKHOUSE_DB` or `POSTGRES_DB` from their defaults, also update the database name
used in [clickhouse/init/01-init.sql](clickhouse/init/01-init.sql) (and, for Postgres, nothing else
needs to change — the official image creates `$POSTGRES_DB` automatically).

## Quick start

```sh
docker compose up -d --build
```

This will:

1. Start PostgreSQL and seed `customers`/`orders` tables, set `REPLICA IDENTITY FULL`, and create the `dbz_publication` publication ([postgres/init/01-init.sql](postgres/init/01-init.sql)).
2. Start ClickHouse and create the `cdc_db` database with `ReplacingMergeTree` target tables ([clickhouse/init/01-init.sql](clickhouse/init/01-init.sql)).
3. Start Kafka, Schema Registry, and Kafka Connect (built from [connect/Dockerfile](connect/Dockerfile), bundling the Debezium PostgreSQL connector, the Confluent JDBC sink connector, the Avro converter, and the ClickHouse JDBC driver).
4. Once Connect is healthy, the one-shot `connect-init` service registers both connectors from [connectors/](connectors/) automatically.
5. Start AKHQ at http://localhost:8080 (Schema Registry wired in, so Avro topics render as decoded JSON in the UI).

Check everything is up:

```sh
docker compose ps
```

If the automatic registration didn't run (e.g. you started Connect separately), register the connectors manually:

```sh
# from Git Bash / WSL / Linux / macOS
sh scripts/register-connectors.sh   # set CONNECT_URL=http://localhost:8083 if running outside the compose network

# from native PowerShell
./scripts/register-connectors.ps1
```

Check connector status any time:

```sh
sh scripts/check-status.sh
```

## Verifying the pipeline

1. Insert a row in Postgres:

   ```sh
   docker exec -it postgres psql -U postgres -d cdc_db -c 
     "INSERT INTO customers (full_name, email) VALUES ('Grace Hopper', 'grace@example.com');"
   ```

2. Confirm the change landed in ClickHouse:

   ```sh
   docker exec -it clickhouse clickhouse-client --query 
     "SELECT * FROM cdc_db.customers_latest ORDER BY id"
   ```

3. Update and delete a row, then re-check `customers_latest` — updates apply in place and deletes disappear from the view (they're soft-deleted under the hood, see below).

4. Watch it happen live in AKHQ (http://localhost:8080): browse the `pg1.public.customers` / `pg1.public.orders` topics for raw CDC events, and the **Kafka Connect** tab for connector/task status.

## Why Avro + Schema Registry

Both connectors use `io.confluent.connect.avro.AvroConverter` for keys and values (see `key.converter`/`value.converter` in [connectors/source/postgres-source.json](connectors/source/postgres-source.json) and [connectors/sink/clickhouse-sink.json](connectors/sink/clickhouse-sink.json)) instead of JSON. Avro encodes each record as compact binary plus a small schema ID, with the full schema stored once in Schema Registry rather than repeated in every message — meaningfully smaller messages and lower Kafka storage/network overhead than schema-carrying JSON, at the cost of needing Schema Registry up before Connect starts (see `depends_on` in [docker-compose.yml](docker-compose.yml)). AKHQ is schema-registry-aware ([akhq/application.yml](akhq/application.yml)) so topics still show up as readable decoded records in the UI rather than raw bytes.

## How the CDC events are shaped

The Debezium source connector uses the `ExtractNewRecordState` SMT (`transforms.unwrap`) to flatten Debezium's `before`/`after`/`op` envelope into a plain "current row" record, adding three bookkeeping fields:

- `__op` — `c` (create), `u` (update), or `d` (delete)
- `__ts_ms` — source event timestamp
- `__deleted` — `true` on delete, since `delete.handling.mode=rewrite` turns deletes into a rewritten record instead of a Kafka tombstone

This shape is what the JDBC sink connector (and ClickHouse) actually receive — see [connectors/source/postgres-source.json](connectors/source/postgres-source.json).

ClickHouse's `MergeTree` family doesn't support in-place `UPDATE`/`DELETE` the way an OLTP database does, so the sink connector only ever `INSERT`s (`insert.mode=insert`). Correctness is recovered on the ClickHouse side:

- Tables use `ReplacingMergeTree(__ts_ms)` keyed on `id`, so the newest version of a row wins.
- The `customers_latest` / `orders_latest` views run `FINAL` (forcing dedup at query time, not waiting for a background merge) and filter out rows where `__deleted = true`.

See [connectors/sink/clickhouse-sink.json](connectors/sink/clickhouse-sink.json) and [clickhouse/init/01-init.sql](clickhouse/init/01-init.sql) for the details.

`created_at`/`updated_at`/`__ts_ms` arrive from Debezium as raw epoch numbers (microseconds for the first two, milliseconds for `__ts_ms`). The sink connector's `TimestampConverter` transforms (`createdAtToTimestamp`/`updatedAtToTimestamp`/`tsMsToTimestamp` in [connectors/sink/clickhouse-sink.json](connectors/sink/clickhouse-sink.json)) convert all three to real `DateTime64(3)` values before they're written, so no conversion is needed on read.

## Repository layout

```
.
├── .env.example            # copy to .env; ports, credentials, db names
├── docker-compose.yml      # all services
├── connect/Dockerfile      # Kafka Connect image: Debezium + JDBC sink + ClickHouse driver
├── postgres/init/          # schema, replica identity, publication, seed data
├── clickhouse/init/        # destination database/tables/views
├── connectors/
│   ├── source/postgres-source.json   # Debezium PostgreSQL source connector config
│   └── sink/clickhouse-sink.json     # Confluent JDBC sink connector config
├── akhq/application.yml    # AKHQ cluster/connect configuration
└── scripts/                # connector registration + status helpers
```

## Adding another table

1. Add the table to `postgres/init/01-init.sql`, with `REPLICA IDENTITY FULL`.
2. Add it to the publication (or recreate `dbz_publication` to include it).
3. Add `public.<table>` to `table.include.list` in `connectors/source/postgres-source.json`.
4. Add the matching topic (`pg1.public.<table>`) to `topics` in `connectors/sink/clickhouse-sink.json`.
5. Create the mirrored `ReplacingMergeTree` table (+ `_latest` view) in `clickhouse/init/01-init.sql`.
6. Re-run `scripts/register-connectors.sh` (or the `.ps1` version) to apply the updated connector configs.

## Tearing down

```sh
docker compose down -v   # -v also drops the named volumes (postgres/kafka/clickhouse data)
```
