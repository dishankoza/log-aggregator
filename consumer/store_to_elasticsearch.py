import json
import os
import time
from datetime import datetime, timezone

from elasticsearch import Elasticsearch
from kafka import KafkaConsumer


KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "otlp_spans")
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:29092")
KAFKA_GROUP = os.getenv("KAFKA_GROUP_ID", "trace-elasticsearch-writer")
ELASTICSEARCH_URL = os.getenv("ELASTICSEARCH_URL", "http://elasticsearch:9200")
ELASTICSEARCH_INDEX = os.getenv("ELASTICSEARCH_INDEX", "trace_spans")


def wait_for_elasticsearch():
    while True:
        try:
            client = Elasticsearch(ELASTICSEARCH_URL)
            if client.ping():
                return client
        except Exception as exc:
            print(f"waiting for elasticsearch: {exc}")
        time.sleep(5)


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


def extract_service_name(resource_span):
    attributes = resource_span.get("resource", {}).get("attributes", [])
    for item in attributes:
        if item.get("key") == "service.name":
            return item.get("value", {}).get("stringValue", "")
    return ""


def extract_attributes(span):
    result = {}
    for item in span.get("attributes", []):
        key = item.get("key")
        value = item.get("value", {})
        if "stringValue" in value:
            result[key] = value["stringValue"]
        elif "intValue" in value:
            result[key] = int(value["intValue"])
        elif "doubleValue" in value:
            result[key] = value["doubleValue"]
        elif "boolValue" in value:
            result[key] = value["boolValue"]
    return result


def ensure_index(client):
    if client.indices.exists(index=ELASTICSEARCH_INDEX):
        return

    client.indices.create(
        index=ELASTICSEARCH_INDEX,
        mappings={
            "properties": {
                "trace_id": {"type": "keyword"},
                "span_id": {"type": "keyword"},
                "parent_span_id": {"type": "keyword"},
                "service_name": {"type": "keyword"},
                "span_name": {"type": "keyword"},
                "span_kind": {"type": "integer"},
                "event_timestamp": {"type": "date"},
                "topic": {"type": "keyword"},
                "partition": {"type": "integer"},
                "offset": {"type": "long"},
                "http_method": {"type": "keyword"},
                "http_route": {"type": "keyword"},
                "http_url": {"type": "wildcard"},
                "status_code": {"type": "integer"},
                "duration_ms": {"type": "float"},
                "payload": {"type": "text"},
            }
        },
    )


def nanos_to_iso8601(value):
    if not value:
        return datetime.now(timezone.utc).isoformat()
    try:
        timestamp = int(value) / 1_000_000_000
        return datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat()
    except Exception:
        return datetime.now(timezone.utc).isoformat()


def nanos_to_duration_ms(start_value, end_value):
    try:
        start = int(start_value)
        end = int(end_value)
        return round((end - start) / 1_000_000, 3)
    except Exception:
        return 0.0


def main():
    es_client = wait_for_elasticsearch()
    ensure_index(es_client)

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
        f"and indexing spans into {ELASTICSEARCH_INDEX}"
    )

    try:
        for message in consumer:
            payload = message.value
            data = json.loads(payload)

            for resource_span in data.get("resourceSpans", []):
                service_name = extract_service_name(resource_span)
                for scope_span in resource_span.get("scopeSpans", []):
                    for span in scope_span.get("spans", []):
                        attrs = extract_attributes(span)
                        document = {
                            "trace_id": span.get("traceId", ""),
                            "span_id": span.get("spanId", ""),
                            "parent_span_id": span.get("parentSpanId", ""),
                            "service_name": service_name,
                            "span_name": span.get("name", ""),
                            "span_kind": span.get("kind", 0),
                            "event_timestamp": nanos_to_iso8601(span.get("startTimeUnixNano", "")),
                            "topic": message.topic,
                            "partition": message.partition,
                            "offset": message.offset,
                            "http_method": attrs.get("http.method", attrs.get("http.request.method", "")),
                            "http_route": attrs.get("http.route", attrs.get("url.path", "")),
                            "http_url": attrs.get("http.url", attrs.get("url.full", "")),
                            "status_code": span.get("status", {}).get("code", 0),
                            "duration_ms": nanos_to_duration_ms(
                                span.get("startTimeUnixNano", ""),
                                span.get("endTimeUnixNano", ""),
                            ),
                            "payload": payload,
                        }
                        es_client.index(index=ELASTICSEARCH_INDEX, document=document)
                        print(
                            f"indexed in elasticsearch topic={message.topic} "
                            f"offset={message.offset} trace_id={document['trace_id']} "
                            f"service={service_name} span={document['span_name']}"
                        )
    finally:
        consumer.close()


if __name__ == "__main__":
    main()
