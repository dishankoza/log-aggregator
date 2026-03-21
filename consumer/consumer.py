import json
import uuid

from kafka import KafkaConsumer

consumer = KafkaConsumer(
    "otlp_spans",
    bootstrap_servers="localhost:9092",
    auto_offset_reset="latest",
    enable_auto_commit=False,
    group_id="trace-debug-consumer",
    value_deserializer=lambda value: value.decode("utf-8"),
)

seen = 0
for message in consumer:
    seen += 1
    print("=" * 80)
    print(
        f"message #{seen} | partition={message.partition} | "
        f"offset={message.offset} | timestamp={message.timestamp}"
    )
    print("-" * 80)
    print(json.dumps(json.loads(message.value), indent=2))
    print()

if seen == 0:
    print("No messages received from otlp_spans within 10 seconds.")
