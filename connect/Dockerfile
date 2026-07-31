FROM confluentinc/cp-kafka-connect-base:7.6.1

ENV CONNECT_PLUGIN_PATH="/usr/share/java,/usr/share/confluent-hub-components"

# Debezium PostgreSQL CDC source connector + Confluent JDBC sink connector + Avro converter
RUN confluent-hub install --no-prompt debezium/debezium-connector-postgresql:2.5.4-2 && \
    confluent-hub install --no-prompt confluentinc/kafka-connect-jdbc:10.7.6 && \
    confluent-hub install --no-prompt confluentinc/kafka-connect-avro-converter:7.6.1

# ClickHouse JDBC driver (shaded, includes HTTP client deps) for the JDBC sink connector.
ADD --chown=appuser:appuser --chmod=644 \
    https://github.com/ClickHouse/clickhouse-java/releases/download/v0.6.3/clickhouse-jdbc-0.6.3-all.jar \
    /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/clickhouse-jdbc-0.6.3-all.jar
