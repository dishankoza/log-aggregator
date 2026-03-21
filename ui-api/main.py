import os
import time
from typing import Any

from cassandra.cluster import Cluster
from elasticsearch import Elasticsearch
from fastapi import FastAPI, Query
from fastapi.responses import FileResponse
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles


ELASTICSEARCH_URL = os.getenv("ELASTICSEARCH_URL", "http://elasticsearch:9200")
ELASTICSEARCH_INDEX = os.getenv("ELASTICSEARCH_INDEX", "trace_spans")
CASSANDRA_HOSTS = os.getenv("CASSANDRA_CONTACT_POINTS", "cassandra").split(",")
CASSANDRA_KEYSPACE = os.getenv("CASSANDRA_KEYSPACE", "observability")
SEARCH_LIMIT = int(os.getenv("SEARCH_LIMIT", "25"))


def wait_for_elasticsearch() -> Elasticsearch:
    while True:
        try:
            client = Elasticsearch(ELASTICSEARCH_URL)
            if client.ping():
                return client
        except Exception:
            pass
        time.sleep(3)


def wait_for_cassandra():
    while True:
        try:
            cluster = Cluster(CASSANDRA_HOSTS)
            session = cluster.connect(CASSANDRA_KEYSPACE)
            return cluster, session
        except Exception:
            time.sleep(3)


def ensure_query_schema(session) -> None:
    session.execute(
        """
        CREATE TABLE IF NOT EXISTS trace_events_by_trace (
            trace_id text,
            event_timestamp timestamp,
            event_id uuid,
            topic text,
            partition int,
            offset bigint,
            service_name text,
            payload text,
            PRIMARY KEY (trace_id, event_timestamp, event_id)
        ) WITH CLUSTERING ORDER BY (event_timestamp DESC, event_id ASC)
        """
    )


es = wait_for_elasticsearch()
cassandra_cluster, cassandra = wait_for_cassandra()
ensure_query_schema(cassandra)

app = FastAPI(title="Trace Search API")
app.mount("/static", StaticFiles(directory="/app/static"), name="static")


@app.get("/")
def root() -> FileResponse:
    return FileResponse("/app/static/index.html")


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/search")
def search(q: str = Query(default="", min_length=0), limit: int = Query(default=SEARCH_LIMIT, le=100)) -> dict[str, Any]:
    if not q.strip():
        body = {
            "size": limit,
            "sort": [{"event_timestamp": {"order": "desc"}}],
            "query": {"match_all": {}},
        }
    else:
        body = {
            "size": limit,
            "sort": [{"_score": {"order": "desc"}}, {"event_timestamp": {"order": "desc"}}],
            "query": {
                "bool": {
                    "should": [
                        {"term": {"trace_id": q}},
                        {"term": {"service_name": q}},
                        {"term": {"span_name": q}},
                        {
                            "multi_match": {
                                "query": q,
                                "fields": ["service_name^3", "span_name^3", "http_route^2", "http_url", "payload"],
                            }
                        },
                    ],
                    "minimum_should_match": 1,
                }
            },
        }

    response = es.search(index=ELASTICSEARCH_INDEX, body=body)
    hits = []
    for hit in response["hits"]["hits"]:
        source = hit["_source"]
        hits.append(
            {
                "trace_id": source.get("trace_id", ""),
                "span_id": source.get("span_id", ""),
                "parent_span_id": source.get("parent_span_id", ""),
                "service_name": source.get("service_name", ""),
                "span_name": source.get("span_name", ""),
                "event_timestamp": source.get("event_timestamp", ""),
                "http_method": source.get("http_method", ""),
                "http_route": source.get("http_route", ""),
                "http_url": source.get("http_url", ""),
                "status_code": source.get("status_code", 0),
                "score": hit.get("_score"),
            }
        )

    return {"query": q, "count": len(hits), "results": hits}


@app.get("/api/traces/{trace_id}")
def trace_details(trace_id: str) -> dict[str, Any]:
    try:
        rows = cassandra.execute(
            """
            SELECT trace_id, event_timestamp, topic, partition, offset, service_name, payload
            FROM trace_events_by_trace
            WHERE trace_id = %s
            """,
            (trace_id,),
        )

        events = []
        for row in rows:
            events.append(
                {
                    "trace_id": row.trace_id,
                    "event_timestamp": row.event_timestamp.isoformat() if row.event_timestamp else "",
                    "topic": row.topic,
                    "partition": row.partition,
                    "offset": row.offset,
                    "service_name": row.service_name,
                    "payload": row.payload,
                }
            )

        return {"trace_id": trace_id, "count": len(events), "events": events}
    except Exception as exc:
        return JSONResponse(
            status_code=500,
            content={"error": "trace_detail_failed", "message": str(exc), "trace_id": trace_id},
        )
