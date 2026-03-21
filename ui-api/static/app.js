const form = document.getElementById("search-form");
const input = document.getElementById("search-input");
const resultsEl = document.getElementById("results");
const resultsCountEl = document.getElementById("results-count");
const detailEl = document.getElementById("trace-detail");
const detailTraceIdEl = document.getElementById("detail-trace-id");

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

form.addEventListener("submit", (event) => {
  event.preventDefault();
  runSearch(input.value.trim());
});

runSearch("");
