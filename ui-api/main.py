import os
import time
from collections import Counter
from typing import Any

from cassandra.cluster import Cluster
from elasticsearch import Elasticsearch
from fastapi import Body, FastAPI, Query
from openai import OpenAI
from fastapi.responses import FileResponse
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles


ELASTICSEARCH_URL = os.getenv("ELASTICSEARCH_URL", "http://elasticsearch:9200")
ELASTICSEARCH_INDEX = os.getenv("ELASTICSEARCH_INDEX", "trace_spans")
CASSANDRA_HOSTS = os.getenv("CASSANDRA_CONTACT_POINTS", "cassandra").split(",")
CASSANDRA_KEYSPACE = os.getenv("CASSANDRA_KEYSPACE", "observability")
SEARCH_LIMIT = int(os.getenv("SEARCH_LIMIT", "25"))
AI_CONTEXT_LIMIT = int(os.getenv("AI_CONTEXT_LIMIT", "8"))
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gemma3:270m")
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL", "").strip()
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "").strip()


def create_llm_client() -> OpenAI | None:
    if OPENAI_BASE_URL:
        return OpenAI(base_url=OPENAI_BASE_URL, api_key=OPENAI_API_KEY or "local-model")
    if OPENAI_API_KEY:
        return OpenAI(api_key=OPENAI_API_KEY)
    return None


openai_client = create_llm_client()


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
    response = es.search(index=ELASTICSEARCH_INDEX, body=build_search_body(q, limit))
    hits = extract_hits(response)

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


def build_search_body(query: str, limit: int) -> dict[str, Any]:
    text = query.strip()
    if not text:
        return {
            "size": limit,
            "sort": [{"event_timestamp": {"order": "desc"}}],
            "query": {"match_all": {}},
        }

    sort = [{"_score": {"order": "desc"}}, {"event_timestamp": {"order": "desc"}}]
    lowered = text.lower()
    if any(word in lowered for word in ["slow", "latency", "delay", "long", "bottleneck"]):
        sort = [{"duration_ms": {"order": "desc"}}, {"event_timestamp": {"order": "desc"}}]

    return {
        "size": limit,
        "sort": sort,
        "query": {
            "bool": {
                "should": [
                    {"term": {"trace_id": text}},
                    {"term": {"service_name": text}},
                    {"term": {"span_name": text}},
                    {
                        "multi_match": {
                            "query": text,
                            "fields": ["service_name^3", "span_name^3", "http_route^2", "http_url", "payload"],
                        }
                    },
                ],
                "minimum_should_match": 1,
            }
        },
    }


def extract_hits(response: dict[str, Any]) -> list[dict[str, Any]]:
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
                "duration_ms": source.get("duration_ms", 0),
                "score": hit.get("_score"),
            }
        )
    return hits


def fetch_trace_events(trace_id: str) -> list[dict[str, Any]]:
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
    return events


def summarize_trace_events(events_by_trace: dict[str, list[dict[str, Any]]]) -> list[dict[str, Any]]:
    summaries = []
    for trace_id, events in events_by_trace.items():
        services = [event.get("service_name", "") for event in events if event.get("service_name")]
        event_counter = Counter(services)
        summaries.append(
            {
                "trace_id": trace_id,
                "event_count": len(events),
                "services": dict(event_counter),
            }
        )
    return summaries


def heuristic_answer(question: str, hits: list[dict[str, Any]], trace_summaries: list[dict[str, Any]]) -> str:
    if not hits:
        return "No matching traces were found in Elasticsearch for that question."

    top = hits[:5]
    parts = []
    if any(word in question.lower() for word in ["slow", "latency", "delay", "long", "bottleneck"]):
        slowest = max(top, key=lambda item: item.get("duration_ms", 0) or 0)
        parts.append(
            f"The strongest latency candidate is span '{slowest.get('span_name')}' in "
            f"{slowest.get('service_name')} at about {slowest.get('duration_ms', 0)} ms."
        )
    services = ", ".join(dict.fromkeys(item.get("service_name", "") for item in top if item.get("service_name")))
    trace_ids = ", ".join(dict.fromkeys(item.get("trace_id", "") for item in top if item.get("trace_id")))
    parts.append(f"Relevant services: {services or 'none identified'}.")
    parts.append(f"Relevant trace ids: {trace_ids or 'none identified'}.")
    if trace_summaries:
        first = trace_summaries[0]
        parts.append(
            f"Top supporting trace {first.get('trace_id', '')} has {first.get('event_count', 0)} raw events "
            f"across services {', '.join(first.get('services', {}).keys()) or 'none'}."
        )
    parts.append("Open a trace detail to inspect the raw Cassandra-backed events.")
    return " ".join(parts)


def build_context(question: str, hits: list[dict[str, Any]]) -> tuple[str, list[str], dict[str, list[dict[str, Any]]]]:
    trace_ids = []
    for hit in hits:
        trace_id = hit.get("trace_id", "")
        if trace_id and trace_id not in trace_ids:
            trace_ids.append(trace_id)
        if len(trace_ids) >= 3:
            break

    trace_context = []
    events_by_trace: dict[str, list[dict[str, Any]]] = {}
    for trace_id in trace_ids:
        events = fetch_trace_events(trace_id)
        events_by_trace[trace_id] = events
        trace_context.append(
            {
                "trace_id": trace_id,
                "events": [
                    {
                        "service_name": event["service_name"],
                        "event_timestamp": event["event_timestamp"],
                        "payload": event["payload"][:3000],
                    }
                    for event in events[:6]
                ],
            }
        )

    search_hits = [
        {
            "trace_id": hit.get("trace_id", ""),
            "service_name": hit.get("service_name", ""),
            "span_name": hit.get("span_name", ""),
            "duration_ms": hit.get("duration_ms", 0),
            "http_route": hit.get("http_route", ""),
            "http_url": hit.get("http_url", ""),
            "event_timestamp": hit.get("event_timestamp", ""),
        }
        for hit in hits[:AI_CONTEXT_LIMIT]
    ]
    return str({"question": question, "search_hits": search_hits, "trace_events": trace_context}), trace_ids, events_by_trace


def build_evidence(hits: list[dict[str, Any]], trace_summaries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    evidence = []
    for hit in hits[:5]:
        evidence.append(
            {
                "kind": "span",
                "trace_id": hit.get("trace_id", ""),
                "service_name": hit.get("service_name", ""),
                "span_name": hit.get("span_name", ""),
                "duration_ms": hit.get("duration_ms", 0),
                "event_timestamp": hit.get("event_timestamp", ""),
                "route": hit.get("http_route", "") or hit.get("http_url", ""),
            }
        )
    for summary in trace_summaries[:3]:
        evidence.append(
            {
                "kind": "trace",
                "trace_id": summary.get("trace_id", ""),
                "event_count": summary.get("event_count", 0),
                "services": list(summary.get("services", {}).keys()),
            }
        )
    return evidence


@app.post("/api/ask")
def ask_ai(payload: dict[str, str] = Body(...)) -> dict[str, Any]:
    question = payload.get("question", "").strip()
    if not question:
        return JSONResponse(status_code=400, content={"error": "question_required"})

    response = es.search(index=ELASTICSEARCH_INDEX, body=build_search_body(question, AI_CONTEXT_LIMIT))
    hits = extract_hits(response)
    context, trace_ids, events_by_trace = build_context(question, hits)
    trace_summaries = summarize_trace_events(events_by_trace)
    evidence = build_evidence(hits, trace_summaries)

    if not openai_client:
        return {
            "mode": "heuristic",
            "answer": heuristic_answer(question, hits, trace_summaries),
            "trace_ids": trace_ids,
            "matches": hits,
            "evidence": evidence,
        }

    try:
        ai_response = openai_client.responses.create(
            model=OPENAI_MODEL,
            instructions=(
                "You are a trace debugging assistant for a distributed system. "
                "Use only the provided trace and span data. "
                "Answer in three short paragraphs: findings, likely cause, and next check. "
                "When discussing latency, call out the slowest span, the affected service, and relevant trace ids. "
                "If the evidence is weak or incomplete, say that explicitly instead of guessing."
            ),
            input=f"User question:\n{question}\n\nTrace context:\n{context}",
        )
        answer = getattr(ai_response, "output_text", "") or "No answer generated."
        mode = "openai"
    except Exception as exc:
        answer = (
            heuristic_answer(question, hits, trace_summaries)
            + f" OpenAI fallback was used because the model request failed: {exc}."
        )
        mode = "heuristic-fallback"

    return {
        "mode": mode,
        "answer": answer,
        "trace_ids": trace_ids,
        "matches": hits,
        "evidence": evidence,
    }
