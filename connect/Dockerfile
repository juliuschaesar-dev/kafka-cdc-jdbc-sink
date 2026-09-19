FROM confluentinc/cp-kafka-connect:8.3.0

ENV CONNECT_PLUGIN_PATH="/usr/share/java,/usr/share/confluent-hub-components"

# Debezium PostgreSQL CDC source connector + Confluent JDBC sink connector + Avro converter
RUN confluent-hub install --no-prompt debezium/debezium-connector-postgresql:3.2.6-3 && \
    confluent-hub install --no-prompt confluentinc/kafka-connect-jdbc:10.9.9 && \
    confluent-hub install --no-prompt confluentinc/kafka-connect-avro-converter:8.3.2

# ClickHouse JDBC driver (shaded, includes HTTP client deps) for the JDBC sink connector.
ADD --chown=appuser:appuser --chmod=644 \
    https://github.com/ClickHouse/clickhouse-java/releases/download/v0.10.0/clickhouse-jdbc-0.10.0-all.jar \
    /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/clickhouse-jdbc-0.10.0-all.jar
