# Phase 09 — OpenTelemetry GenAI Semconv Emission

**Status:** Draft
**Phase:** 09 (A+ Roadmap)
**Priority:** P1
**Author:** forge maintainers
**Date:** 2026-04-19
**Depends on:** Phase 02 (Cross-Platform Python Hooks)

---

## 1. Goal

Replace `shared/forge-otel-export.sh` with a Python-native emitter
(`hooks/_py/otel.py`) that streams OpenTelemetry **GenAI Semantic Conventions
(2026)** spans — per pipeline, per stage, and per agent dispatch — so any
compliant backend (Datadog, Arize, LangSmith, Honeycomb, Grafana Tempo) can
ingest forge telemetry without custom attribute mapping.

## 2. Motivation

### Audit W9 — off-spec telemetry

`shared/forge-otel-export.sh` ships 210 LOC of bash + inline Python that:

1. Reads `state.json.telemetry.spans` post-hoc (LEARNING stage only).
2. Emits **custom attribute names** (`tokens_in`, `tokens_out`,
   `findings_count`, `agent`, `model`) that no observability vendor recognizes.
3. POSTs OTLP/HTTP/JSON one-shot at end of run — spans cannot be correlated
   live, and a crashed run produces no telemetry at all.
4. Has no trace context propagation: every run is a flat trace with MD5-derived
   span IDs that collide across identical story IDs.

### The 2026 GenAI semconv

The OpenTelemetry GenAI Semantic Conventions (stable April 2026) define a
vendor-neutral schema for LLM/agent workloads:

- **Spec:** <https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-agent-spans/>
- **Attributes:** `gen_ai.agent.name`, `gen_ai.agent.description`,
  `gen_ai.agent.id`, `gen_ai.tool.calls`, `gen_ai.tokens.input`,
  `gen_ai.tokens.output`, `gen_ai.tokens.total`, `gen_ai.cost.usd`,
  `gen_ai.request.model`, `gen_ai.operation.name`, `gen_ai.response.finish_reasons`.
- **Operation names:** `invoke_agent`, `execute_tool`, `create_agent`.

Every major observability vendor — Datadog (April 2026 release),
Arize Phoenix, LangSmith OTLP bridge, Grafana Tempo, Honeycomb — ships
**pre-built dashboards and filters keyed on these attributes**. Custom
attribute names force every forge user to hand-write view definitions.

Aligning forge with the semconv is a one-time refactor that unlocks
drop-in integration with every agentic observability platform.

## 3. Scope

### In scope

1. **New Python emitter** at `hooks/_py/otel.py` (depends on Phase 02).
2. **Spans emitted:**
   - Root `pipeline` span per run (operation: `invoke_agent`, agent name
     = `forge-pipeline`).
   - `stage` child span per pipeline stage: PREFLIGHT, EXPLORING, PLANNING,
     VALIDATING, IMPLEMENTING, VERIFYING, REVIEWING, DOCUMENTING, SHIPPING,
     LEARNING.
   - `agent` child span per subagent dispatch (one per `Agent(...)` call).
   - `tool` child span per tool invocation within an agent (when enabled).
3. **Attributes populated per 2026 GenAI semconv:**
   - Agent spans: `gen_ai.agent.name`, `gen_ai.agent.description`,
     `gen_ai.agent.id`, `gen_ai.operation.name`, `gen_ai.request.model`,
     `gen_ai.tokens.input`, `gen_ai.tokens.output`, `gen_ai.tokens.total`,
     `gen_ai.cost.usd`, `gen_ai.tool.calls` (int), `gen_ai.response.finish_reasons`.
   - Pipeline/stage spans: same envelope + `forge.*` namespace for
     forge-specific attributes (`forge.run_id`, `forge.stage`, `forge.mode`,
     `forge.score`, `forge.convergence.iterations`).
4. **Supported exporters:** OTLP/gRPC (default), OTLP/HTTP (JSON + protobuf),
   console (debug).
5. **Trace context propagation** across Task-tool subagent dispatches via W3C
   Trace Context (`TRACEPARENT`, `TRACESTATE` env vars).
6. **Event-sourced emission:** spans are *built from* `.forge/events.jsonl`
   (Phase F07), not from `state.json.telemetry`. Emitter tails the event log
   and translates each event → span open/close.
7. **Live streaming:** spans flushed in batches of 32 or every 2s (whichever
   first) so a crashed run still produces partial telemetry.
8. **Configuration** via `observability.otel.*` keys in `forge-config.md`.
9. **Schema validator test** in CI ensuring every emitted span passes the
   OTel semconv JSON Schema.

### Out of scope

- Metrics pipeline (histograms, counters, gauges) — **Phase 10**. This spec
  covers traces only.
- Logs / log correlation beyond the `trace_id` and `span_id` embedded in
  log records — later.
- Automatic instrumentation of the Claude API SDK (the harness already
  handles LLM calls; forge only instruments the *agent dispatch* layer).
- Legacy dashboards based on `tokens_in` / `tokens_out` custom names.

## 4. Architecture

### 4.1 Python module layout

```
hooks/
  _py/
    otel.py                     # NEW -- public emitter API
    otel_attributes.py          # NEW -- semconv constant strings (frozen)
    otel_exporters.py           # NEW -- thin wrappers over opentelemetry-exporter-otlp
    otel_context.py             # NEW -- W3C Trace Context propagation helpers
    event_to_span.py            # NEW -- translator: events.jsonl row -> span ops
```

### 4.2 Dependencies (minimal)

- `opentelemetry-api >= 1.30.0`
- `opentelemetry-sdk >= 1.30.0`
- `opentelemetry-exporter-otlp >= 1.30.0` (covers gRPC + HTTP)
- stdlib only beyond that

Dependencies vendored as an optional extra: `forge[otel]`. When missing, the
emitter logs `WARNING: opentelemetry not installed — OTel export disabled`
and the pipeline continues unchanged. **No silent degradation to the old
custom exporter** — it is deleted in the same PR.

### 4.3 Lifecycle

1. **PREFLIGHT** — orchestrator calls `otel.init(config)`.
   - Reads `observability.otel.*` from `forge-config.md`.
   - If disabled → `otel.init` returns a no-op shim. All subsequent calls
     short-circuit.
   - If enabled → constructs `TracerProvider` + configured exporter +
     `BatchSpanProcessor` (batch=32, flush=2s).
   - Opens the root `pipeline` span; sets it as the active context.
   - Writes `TRACEPARENT` into the environment so child processes inherit.
2. **Stage transition** — orchestrator calls `otel.stage_start(name)` /
   `otel.stage_end(name, attrs)`. Spans nest under the active stage context.
3. **Agent dispatch** — the orchestrator wraps `Agent(...)` calls:

       with otel.agent_span(agent_name, model, description):
           result = Agent(...)
           otel.record_agent_result(result)  # tokens, cost, tool_calls, findings

4. **Subagent context propagation** — before dispatching a Task subagent,
   orchestrator injects `TRACEPARENT` into the subagent's environment. The
   subagent's own `otel.init` picks it up and continues the trace.
5. **LEARNING** — retrospective closes remaining spans; emitter calls
   `TracerProvider.shutdown()` which flushes pending batches.
6. **Event-sourced fallback** — if a run crashed and spans never flushed, a
   post-run `otel replay --from-events .forge/events.jsonl` command rebuilds
   spans from the event log and exports them. This is the *only* path the
   legacy `forge-otel-export.sh` covered; we keep it but move it to Python.

### 4.4 Span/attribute mapping

| forge concept | OTel span | `gen_ai.operation.name` | Key attributes |
|---|---|---|---|
| Pipeline run | `pipeline` | `invoke_agent` | `gen_ai.agent.name=forge-pipeline`, `forge.run_id`, `forge.mode` |
| Stage | `stage.<STAGE>` | (none; forge custom) | `forge.stage`, `forge.phase_iterations` |
| Agent dispatch | `agent.<agent_name>` | `invoke_agent` | `gen_ai.agent.name`, `gen_ai.agent.description`, `gen_ai.request.model`, `gen_ai.tokens.*`, `gen_ai.cost.usd`, `gen_ai.tool.calls` |
| Review batch | `batch.review-round-<N>` | (none; forge custom) | `forge.batch.size`, `forge.batch.agents` |
| Tool call (optional) | `tool.<tool_name>` | `execute_tool` | `gen_ai.tool.name`, `gen_ai.tool.call.id` |

Stage and batch spans are forge-specific — semconv does not prescribe
`gen_ai.operation.name` for them, which is explicitly allowed. Only agent
and tool spans carry the `gen_ai.operation.name` field.

### 4.5 Trace context propagation

W3C Trace Context is the *only* supported propagator. The orchestrator:

1. Serializes the active span context to a `TRACEPARENT` header string
   (`{version}-{trace_id}-{span_id}-{flags}`).
2. Sets `TRACEPARENT=<value>` in the subagent's environment (the Task tool
   inherits parent env unless overridden).
3. Subagents call `otel.init(config, parent_traceparent=os.environ.get("TRACEPARENT"))`
   which invokes `TraceContextTextMapPropagator().extract(...)` and rehydrates
   the parent context.

Baggage (`TRACESTATE`) is forwarded unchanged so vendor-specific trace
enrichment (Datadog service, Honeycomb dataset) survives dispatch.

### 4.6 Alternatives considered

**A. Keep a custom forge schema and publish a converter.**
Rejected. Every vendor would need per-forge plumbing; maintaining a
translator is a permanent tax. The semconv schema is now stable and covers
100% of what forge emits.

**B. Adopt OpenInference (Arize's agent semconv).**
Rejected as primary schema. OpenInference pre-dates the OTel GenAI spec and
is Arize-centric; Datadog/Honeycomb/LangSmith default to the OTel schema.
OpenInference attributes can be emitted *in addition* behind a feature flag
(`observability.otel.openinference_compat: true`) for Arize-heavy users —
kept out of v1 scope.

## 5. Components

### New

- `hooks/_py/otel.py` — public API: `init()`, `shutdown()`,
  `stage_span(name)`, `agent_span(name, model, description)`,
  `tool_span(name)`, `record_agent_result(result)`, `replay(events_path)`.
- `hooks/_py/otel_attributes.py` — frozen string constants for every
  semconv attribute name (single source of truth; prevents typos).
- `hooks/_py/otel_exporters.py` — exporter factory keyed on
  `observability.otel.exporter`.
- `hooks/_py/otel_context.py` — W3C propagation helpers.
- `hooks/_py/event_to_span.py` — translator used by `otel.replay()`.
- `shared/schemas/otel-genai-v1.json` — local copy of the semconv JSON
  Schema for CI validation (pinned version, upgraded manually).

### Modified

- `shared/observability.md` — rewritten to document semconv attributes,
  new config keys, and replay flow. Old `forge.*` attribute docs removed
  from the span schema section.
- `agents/fg-100-orchestrator.md` — adds `otel.stage_span()` wrapper around
  every stage transition and `otel.agent_span()` around every dispatch.
  Documents the `TRACEPARENT` env-var contract for Task dispatches.
- `hooks/_py/state_write.py` (from Phase 02) — calls `otel.emit_event_mirror()`
  after every event append so spans stay in lockstep with
  `.forge/events.jsonl`.
- `shared/preflight-constraints.md` — adds the `observability.otel.*`
  validation table.
- `plugin.json` — declares optional `[otel]` extra so `pip install forge[otel]`
  pulls the OTel SDK.

### Deleted

- `shared/forge-otel-export.sh` (210 LOC). Replaced wholesale by
  `otel.replay()`.

## 6. Data / State / Config

### Configuration keys (`forge-config.md`)

```yaml
observability:
  otel:
    enabled: false                      # opt-in; default OFF
    endpoint: "http://localhost:4317"   # OTLP collector (gRPC) or HTTP URL
    exporter: grpc                      # grpc | http | console
    service_name: forge-pipeline
    sample_rate: 1.0                    # 0.0-1.0; forge runs are rare, default 100%
    openinference_compat: false         # emit OpenInference attrs alongside semconv
    include_tool_spans: false           # emit tool-level spans (noisy)
    batch_size: 32
    flush_interval_seconds: 2
```

Old keys (`observability.export`, `observability.otel_endpoint`) are
**removed**. The legacy `export: local` mode (JSON in `state.json.telemetry`)
remains the default when `otel.enabled` is `false` — that path already works
and is handled outside this module.

### State

No state schema changes. `.forge/events.jsonl` is the source of truth;
the OTel emitter is a read-only consumer.

### PREFLIGHT constraints

| Parameter | Constraint | Default |
|---|---|---|
| `observability.otel.enabled` | bool | `false` |
| `observability.otel.endpoint` | non-empty when enabled | `""` |
| `observability.otel.exporter` | one of `grpc`/`http`/`console` | `grpc` |
| `observability.otel.service_name` | non-empty | `forge-pipeline` |
| `observability.otel.sample_rate` | 0.0–1.0 | `1.0` |
| `observability.otel.batch_size` | 1–1024 | `32` |
| `observability.otel.flush_interval_seconds` | 1–60 | `2` |

Violations log WARNING and fall back to defaults. If `enabled=true` but
`opentelemetry-api` is not importable → WARNING + disable for the run.

## 7. Compatibility

**Breaking.** No backwards compatibility is preserved, per project policy.

- `shared/forge-otel-export.sh` is deleted. Any user workflow that invoked
  it directly (no known consumers outside the plugin) breaks.
- Custom attribute names (`tokens_in`, `tokens_out`, `findings_count`,
  `agent`, `model` at the top level) are removed. Existing dashboards keyed
  on those names break and must be rebuilt against `gen_ai.*`.
- Configuration keys `observability.export` and `observability.otel_endpoint`
  are removed. Users must update `forge-config.md` to the nested
  `observability.otel.*` form.
- The `telemetry.export_status` field in `state.json` is no longer written.
  (Retrospective analytics read from events, not state.)

Migration notes are added to `CHANGELOG.md` in the release PR.

## 8. Testing Strategy

Per project policy: **no local test execution.** CI drives all verification.

### CI additions (`.github/workflows/test.yml`)

1. **`otel-semconv-validation` job** (new):
   - Spin up `otel/opentelemetry-collector-contrib:0.105.0` in Docker with a
     file exporter writing JSON to `/tmp/otel-out.jsonl`.
   - Run the existing Phase 01 eval scenario with `observability.otel.enabled=true`
     and `exporter=grpc`, endpoint pointed at the collector.
   - Load `shared/schemas/otel-genai-v1.json` (pinned semconv schema).
   - Python validator script (`tests/otel_semconv_validator.py`) iterates
     every emitted span and asserts:
     - Required agent-span attributes present (`gen_ai.agent.name`,
       `gen_ai.request.model`, `gen_ai.operation.name`).
     - `gen_ai.tokens.total == tokens.input + tokens.output` (consistency).
     - Span parent/child hierarchy matches forge's stage tree.
     - `TRACEPARENT` propagated — every subagent span shares the root
       `trace_id` of the pipeline span.
   - Fails the job on any schema violation.
2. **`otel-replay` job** — runs `otel.replay()` against a recorded
   `events.jsonl` fixture and asserts parity with the live exporter output
   (spans/attributes equivalent modulo timing).
3. **`otel-disabled` smoke test** — runs eval with `otel.enabled=false`,
   asserts zero OTel-related log lines and no performance regression
   (>5% over the baseline fails the job).

### Vendor integration (manual, release checklist)

Before cutting a release, maintainers run the eval scenario pointed at:

- Datadog agent (OTLP/gRPC) — confirms the "GenAI" view populates.
- Arize Phoenix (OTLP/HTTP) — confirms agent graph renders.
- Grafana Tempo (OTLP/gRPC) — confirms trace search by `gen_ai.agent.name`.

Results logged in the release PR description. Not a CI gate.

## 9. Rollout

1. **Merge Phase 02 first.** This phase imports `hooks/_py/` and depends on
   cross-platform Python hooks being the default path.
2. **Single PR for Phase 09** containing:
   - All new `hooks/_py/otel*.py` modules.
   - Deletion of `shared/forge-otel-export.sh`.
   - `shared/observability.md` rewrite.
   - `agents/fg-100-orchestrator.md` updates.
   - CI workflow additions.
   - `CHANGELOG.md` breaking-change notice.
3. **No feature flag / dual-path.** Users opt in via
   `observability.otel.enabled: true`; when off, zero OTel code runs.
4. **Release as forge 3.1.0** (minor bump; breaking changes allowed since
   project explicitly disclaims backwards compatibility, but bumping signals
   config-file updates required).

## 10. Risks / Open Questions

### Risks

- **Semconv churn.** The GenAI spec is "stable" but the OTel working group
  has signalled minor additions (`gen_ai.agent.thread.id`). Mitigation: pin
  the schema version in `shared/schemas/otel-genai-v1.json` and track drift
  manually. Quarterly audit.
- **Collector availability in CI.** Docker-in-docker sometimes flakes on
  GitHub Actions macOS runners. Mitigation: gate the
  `otel-semconv-validation` job to `ubuntu-latest` only — Linux collector
  image is reliable.
- **Batch loss on crash.** The 2s flush window means up to 2s of spans can
  be lost if the pipeline hard-crashes. Mitigation: `otel.replay()` rebuilds
  from `events.jsonl` post-hoc; users can schedule it in their CI failure
  handler.
- **Cost attribution accuracy.** `gen_ai.cost.usd` requires model-price
  lookups. Mitigation: reuse `shared/model-routing.md` pricing table;
  fall back to `0.0` with a `forge.cost.unknown=true` attribute when the
  model isn't in the table.

### Open questions

- Do we emit a `gen_ai.prompt` attribute containing the agent's rendered
  system prompt? It's ~kilobytes per span and PII-sensitive. **Proposed
  default:** no; add `observability.otel.include_prompts: false` toggle
  (opt-in, redaction via `shared/data-classification.md`).
- Should review-batch spans use `gen_ai.operation.name=invoke_agent` with
  `gen_ai.agent.name=review-batch-<N>`, or stay forge-custom? **Proposed:**
  stay forge-custom (`forge.batch`) since the batch isn't an agent per
  semconv — it's a coordination construct.

## 11. Success Criteria

1. Every span emitted during an eval run passes the pinned OTel GenAI
   Semantic Conventions JSON Schema — **zero** schema violations in the
   `otel-semconv-validation` CI job.
2. A forge run with `otel.enabled=true` renders a complete trace in each
   of: Datadog (GenAI Monitoring view), Arize Phoenix (agent graph),
   Grafana Tempo (trace search) **without any user-written attribute
   mapping or remapping rule**.
3. Trace context propagation verified: every subagent span shares the
   pipeline's `trace_id`; no orphan traces.
4. `observability.otel.enabled=false` incurs <1ms overhead per stage
   transition and zero OTel module imports (lazy-loaded).
5. `otel.replay()` produces byte-equivalent spans (modulo timestamps) to
   live emission when given the same `events.jsonl` — deterministic
   replay.
6. Phase 02 dependency graph clean: `hooks/_py/otel.py` imports only from
   `hooks/_py/` + stdlib + `opentelemetry.*`; no bash callouts.

## 12. References

- OpenTelemetry GenAI Agent Spans spec:
  <https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-agent-spans/>
- OpenTelemetry GenAI attributes:
  <https://opentelemetry.io/docs/specs/semconv/attributes-registry/gen-ai/>
- W3C Trace Context: <https://www.w3.org/TR/trace-context/>
- Datadog GenAI Monitoring (OTLP ingestion):
  <https://docs.datadoghq.com/llm_observability/instrumentation/otel_instrumentation/>
- Arize Phoenix OTLP tracing:
  <https://docs.arize.com/phoenix/tracing/how-to-tracing/setup-tracing>
- LangSmith OTLP bridge:
  <https://docs.smith.langchain.com/observability/how_to_guides/monitoring/opentelemetry>
- Grafana Tempo OTLP:
  <https://grafana.com/docs/tempo/latest/api_docs/pushing-spans-with-http/>
- Honeycomb OTLP:
  <https://docs.honeycomb.io/send-data/opentelemetry/>
- OpenInference semconv (alternative schema, deferred):
  <https://github.com/Arize-ai/openinference/blob/main/spec/semantic_conventions.md>
- forge Phase 02 spec: `docs/superpowers/specs/2026-04-19-02-cross-platform-python-hooks-design.md`
- forge event-sourced log (F07): `shared/event-log.md`
- forge current exporter (to be deleted): `shared/forge-otel-export.sh`
- forge current observability doc (to be rewritten): `shared/observability.md`
