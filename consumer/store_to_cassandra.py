import json
import os
import time
import uuid
from datetime import datetime, timezone

from cassandra.cluster import Cluster
from kafka import KafkaConsumer


KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "otlp_spans")
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:29092")
KAFKA_GROUP = os.getenv("KAFKA_GROUP_ID", "trace-cassandra-writer")

CASSANDRA_HOSTS = os.getenv("CASSANDRA_CONTACT_POINTS", "cassandra").split(",")
CASSANDRA_KEYSPACE = os.getenv("CASSANDRA_KEYSPACE", "observability")
CASSANDRA_TABLE = os.getenv("CASSANDRA_TABLE", "trace_events")


def wait_for_cassandra():
    while True:
        try:
            cluster = Cluster(CASSANDRA_HOSTS)
            session = cluster.connect()
            return cluster, session
        except Exception as exc:
            print(f"waiting for cassandra: {exc}")
            time.sleep(5)


def ensure_schema(session):
    session.execute(
        f"""
        CREATE KEYSPACE IF NOT EXISTS {CASSANDRA_KEYSPACE}
        WITH replication = {{'class': 'SimpleStrategy', 'replication_factor': 1}}
        """
    )
    session.set_keyspace(CASSANDRA_KEYSPACE)
    session.execute(
        f"""
        CREATE TABLE IF NOT EXISTS {CASSANDRA_TABLE} (
            topic text,
            event_date text,
            event_id uuid,
            event_timestamp timestamp,
            partition int,
            offset bigint,
            trace_id text,
            service_name text,
            payload text,
            PRIMARY KEY ((topic, event_date), event_timestamp, event_id)
        ) WITH CLUSTERING ORDER BY (event_timestamp DESC, event_id ASC)
        """
    )


def extract_first(data, path, default=""):
    current = data
    for key in path:
        if isinstance(key, int):
            if not isinstance(current, list) or len(current) <= key:
                return default
            current = current[key]
            continue
        if not isinstance(current, dict) or key not in current:
            return default
        current = current[key]
    return current


def extract_service_name(data):
    attributes = extract_first(data, ["resourceSpans", 0, "resource", "attributes"], default=[])
    if not isinstance(attributes, list):
        return ""
    for item in attributes:
        if item.get("key") == "service.name":
            return item.get("value", {}).get("stringValue", "")
    return ""


def main():
    cluster, session = wait_for_cassandra()
    ensure_schema(session)

    insert = session.prepare(
        f"""
        INSERT INTO {CASSANDRA_TABLE}
        (topic, event_date, event_id, event_timestamp, partition, offset, trace_id, service_name, payload)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
    )

    consumer = KafkaConsumer(
        KAFKA_TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP,
        auto_offset_reset="latest",
        enable_auto_commit=True,
        group_id=KAFKA_GROUP,
        value_deserializer=lambda value: value.decode("utf-8"),
    )

    print(
        f"consuming topic={KAFKA_TOPIC} from {KAFKA_BOOTSTRAP} "
        f"and storing raw payloads in {CASSANDRA_KEYSPACE}.{CASSANDRA_TABLE}"
    )

    try:
        for message in consumer:
            payload = message.value
            data = json.loads(payload)
            trace_id = extract_first(
                data, ["resourceSpans", 0, "scopeSpans", 0, "spans", 0, "traceId"]
            )
            service_name = extract_service_name(data)

            now = datetime.now(timezone.utc)
            session.execute(
                insert,
                (
                    message.topic,
                    now.date().isoformat(),
                    uuid.uuid4(),
                    now,
                    message.partition,
                    message.offset,
                    trace_id,
                    service_name,
                    payload,
                ),
            )
            print(
                f"stored in cassandra topic={message.topic} partition={message.partition} "
                f"offset={message.offset} trace_id={trace_id} service={service_name}"
            )
    finally:
        consumer.close()
        session.shutdown()
        cluster.shutdown()


if __name__ == "__main__":
    main()
