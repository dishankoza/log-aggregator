const form = document.getElementById("search-form");
const input = document.getElementById("search-input");
const aiForm = document.getElementById("ai-form");
const aiInput = document.getElementById("ai-input");
const resultsEl = document.getElementById("results");
const resultsCountEl = document.getElementById("results-count");
const detailEl = document.getElementById("trace-detail");
const detailTraceIdEl = document.getElementById("detail-trace-id");
const aiAnswerEl = document.getElementById("ai-answer");
const aiModeEl = document.getElementById("ai-mode");

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function renderResults(results) {
  resultsCountEl.textContent = String(results.length);

  if (results.length === 0) {
    resultsEl.innerHTML = '<div class="results-empty">No matching spans found.</div>';
    return;
  }

  resultsEl.innerHTML = results
    .map(
      (item) => `
        <article class="result-item" data-trace-id="${item.trace_id}">
          <div class="result-top">
            <div>
              <div class="service-pill">${escapeHtml(item.service_name || "unknown-service")}</div>
              <h3>${escapeHtml(item.span_name || "unnamed-span")}</h3>
            </div>
            <div class="meta">${escapeHtml(item.event_timestamp || "")}</div>
          </div>
          <div class="meta">trace: ${escapeHtml(item.trace_id || "")}</div>
          <div class="meta">route: ${escapeHtml(item.http_route || item.http_url || "")}</div>
          <div class="meta">duration: ${escapeHtml(String(item.duration_ms || 0))} ms</div>
        </article>
      `
    )
    .join("");

  document.querySelectorAll(".result-item").forEach((node) => {
    node.addEventListener("click", () => loadTrace(node.dataset.traceId));
  });
}

function renderTraceDetail(traceId, events) {
  detailTraceIdEl.textContent = traceId;

  if (events.length === 0) {
    detailEl.innerHTML = '<div class="results-empty">No Cassandra events found for this trace.</div>';
    return;
  }

  detailEl.innerHTML = events
    .map(
      (event) => `
        <article class="detail-item">
          <div class="detail-top">
            <div class="service-pill">${escapeHtml(event.service_name || "unknown-service")}</div>
            <div class="meta">${escapeHtml(event.event_timestamp || "")}</div>
          </div>
          <div class="meta">partition=${event.partition} offset=${event.offset}</div>
          <pre>${escapeHtml(JSON.stringify(JSON.parse(event.payload), null, 2))}</pre>
        </article>
      `
    )
    .join("");
}

function renderAiEvidence(evidence) {
  if (!evidence || evidence.length === 0) {
    return '<div class="results-empty">No supporting traces were attached to this answer.</div>';
  }

  return evidence
    .map((item) => {
      if (item.kind === "trace") {
        return `
          <article class="detail-item">
            <div class="detail-top">
              <div class="service-pill">TRACE</div>
              <div class="meta">${escapeHtml(item.trace_id || "")}</div>
            </div>
            <div class="meta">raw events: ${escapeHtml(String(item.event_count || 0))}</div>
            <div class="meta">services: ${escapeHtml((item.services || []).join(", "))}</div>
          </article>
        `;
      }

      return `
        <article class="detail-item">
          <div class="detail-top">
            <div class="service-pill">${escapeHtml(item.service_name || "unknown-service")}</div>
            <div class="meta">${escapeHtml(item.event_timestamp || "")}</div>
          </div>
          <div class="meta">trace: ${escapeHtml(item.trace_id || "")}</div>
          <div class="meta">span: ${escapeHtml(item.span_name || "unnamed-span")}</div>
          <div class="meta">route: ${escapeHtml(item.route || "")}</div>
          <div class="meta">duration: ${escapeHtml(String(item.duration_ms || 0))} ms</div>
        </article>
      `;
    })
    .join("");
}

async function runSearch(query) {
  resultsEl.innerHTML = '<div class="results-empty">Searching...</div>';
  const response = await fetch(`/api/search?q=${encodeURIComponent(query)}`);
  const data = await response.json();
  renderResults(data.results || []);
}

async function loadTrace(traceId) {
  detailEl.innerHTML = '<div class="results-empty">Loading trace detail from Cassandra...</div>';
  const response = await fetch(`/api/traces/${encodeURIComponent(traceId)}`);
  const text = await response.text();
  let data;

  try {
    data = JSON.parse(text);
  } catch {
    detailEl.innerHTML = `<div class="results-empty">Trace detail request failed: ${escapeHtml(text)}</div>`;
    return;
  }

  if (!response.ok) {
    detailEl.innerHTML =
      `<div class="results-empty">Trace detail request failed: ${escapeHtml(data.message || "unknown error")}</div>`;
    return;
  }

  renderTraceDetail(traceId, data.events || []);
}

async function askAi(question) {
  if (!question) {
    aiModeEl.textContent = "idle";
    aiAnswerEl.innerHTML = '<div class="results-empty">Enter a debugging question first.</div>';
    return;
  }

  aiModeEl.textContent = "thinking";
  aiAnswerEl.innerHTML = '<div class="results-empty">Analyzing traces...</div>';

  const response = await fetch("/api/ask", {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({question}),
  });
  const data = await response.json();

  if (!response.ok) {
    aiModeEl.textContent = "error";
    aiAnswerEl.innerHTML =
      `<div class="results-empty">AI request failed: ${escapeHtml(data.message || data.error || "unknown error")}</div>`;
    return;
  }

  aiModeEl.textContent = data.mode || "ok";
  aiAnswerEl.innerHTML = `
    <article class="detail-item ai-summary">
      <div class="detail-top">
        <div class="service-pill">${escapeHtml((data.mode || "ai").toUpperCase())}</div>
        <div class="meta">${escapeHtml((data.trace_ids || []).join(", "))}</div>
      </div>
      <pre>${escapeHtml(data.answer || "")}</pre>
    </article>
    <div class="panel-subtitle">Supporting evidence</div>
    ${renderAiEvidence(data.evidence || [])}
  `;

  if (data.matches && data.matches.length > 0) {
    renderResults(data.matches);
  }
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  runSearch(input.value.trim());
});

aiForm.addEventListener("submit", (event) => {
  event.preventDefault();
  askAi(aiInput.value.trim());
});

runSearch("");
