# Observability

forge emits OpenTelemetry GenAI Semantic Conventions (2026) spans via
`hooks/_py/otel.py`. Any compliant backend (Datadog, Arize Phoenix,
LangSmith, Grafana Tempo, Honeycomb) ingests forge telemetry without
custom attribute mapping.

## Durability contract

- **Live stream is best-effort.** `BatchSpanProcessor` flushes every
  `observability.otel.flush_interval_seconds` or when
  `observability.otel.batch_size` is reached. A hard crash drops the
  in-memory batch.
- **`otel.replay()` is authoritative.** The event log
  (`.forge/events.jsonl`) is fsync'd per row (Phase F07); `replay` rebuilds
  and re-emits spans deterministically. Schedule it in CI failure handlers:

      python -m hooks._py.otel_cli replay --from-events .forge/events.jsonl \
                                         --exporter grpc \
                                         --endpoint http://collector:4317

## Sampler

`ParentBased(root=TraceIdRatioBased(sample_rate))`. Subagents always honour
the parent decision, preventing orphan partial traces. An inbound
`TRACEPARENT` with `sampled=0` is respected — the child emits nothing.

## Trace-context propagation

Before every subagent dispatch, orchestrator calls
`otel.dispatch_env(os.environ)` which injects `TRACEPARENT` (and
`TRACESTATE` when baggage is present) into the child env per W3C Trace
Context. The subagent's `otel.init(..., parent_traceparent=os.environ.get("TRACEPARENT"))`
rehydrates the parent context.

## Attributes

### Agent spans (`gen_ai.operation.name = invoke_agent`)

- `gen_ai.agent.name`, `gen_ai.agent.description`, `gen_ai.agent.id`
- `gen_ai.request.model`
- `gen_ai.tokens.input`, `gen_ai.tokens.output`, `gen_ai.tokens.total`
- `gen_ai.cost.usd` (falls back to `forge.cost.unknown=true` when the
  model is absent from `shared/model-routing.md` pricing table)
- `gen_ai.tool.calls`
- `gen_ai.response.finish_reasons`
- `forge.run.budget_total_usd` (double) — configured ceiling
- `forge.run.budget_remaining_usd` (double) — at span start
- `forge.agent.tier_estimate_usd` (double) — per-iteration estimate for resolved tier
- `forge.agent.tier_original` (string, enum: fast|standard|premium) — tier from static routing before downgrade
- `forge.agent.tier_used` (string, enum: fast|standard|premium) — tier actually dispatched
- `forge.cost.throttle_reason` (string, enum: none|soft_20pct|soft_10pct|ceiling_breach|dynamic_downgrade)

### Pipeline / stage / batch spans

- Carry `forge.*` attributes: `forge.run_id`, `forge.stage`, `forge.mode`,
  `forge.score`, `forge.phase_iterations`, `forge.convergence.iterations`,
  `forge.batch.size`, `forge.batch.agents`.

### Phase 7 spans (intent verification + implementer voting)

| Span name | Cardinality | Attributes |
|---|---|---|
| `forge.intent.verify_ac` | one per AC verified | `forge.intent.ac_id`, `forge.intent.ac_verdict`, `forge.intent.probe_tier`, `forge.intent.probes_issued`, `forge.intent.duration_ms` |
| `forge.impl.vote` | one per voted sample | `forge.impl_vote.task_id`, `forge.impl_vote.sample_id`, `forge.impl_vote.trigger`, `forge.impl_vote.verdict`, `forge.impl_vote.ast_fingerprint`, `forge.impl_vote.degraded` |

---

### Learning events (Phase 4)

Four event types are emitted via `emit_event_mirror` (never
`span.add_event`) inside the active `agent_span`. Events are written first
to `.forge/events.jsonl` (fsync'd) and mirrored onto the span as
attributes, so `otel.replay` is authoritative.

| Event type                          | Emitter                           | Purpose                                |
|-------------------------------------|-----------------------------------|----------------------------------------|
| `forge.learning.injected`           | orchestrator (per selected item)  | Records that a learning was shown.     |
| `forge.learning.applied`            | orchestrator (on marker parse)    | Records reinforcement signal.          |
| `forge.learning.fp`                 | orchestrator (on marker parse)    | Records false-positive signal.         |
| `forge.learning.vindicated`         | user / retrospective override     | Restores base_confidence from snapshot.|

Attributes (registered in `hooks/_py/otel_attributes.py`):

| Attribute name                  | Cardinality | Typical value                        |
|---------------------------------|-------------|--------------------------------------|
| `forge.learning.id`             | ~500 items  | `"ks-preempt-001"`                   |
| `forge.learning.confidence_now` | float       | `0.82`                               |
| `forge.learning.applied_count`  | int         | `3`                                  |
| `forge.learning.source_path`    | ~50 files   | `"shared/learnings/spring.md"`       |
| `forge.learning.reason`         | free text   | `"not applicable for this task"`    |

All `forge.learning.*` attributes are UNBOUNDED — never fold into span names.

## Namespace Contract (forge 3.7.0+)

All forge-emitted span attributes MUST use the `forge.*` root. OpenTelemetry semconv attributes (`gen_ai.*`) remain unchanged. The contract is:

| Prefix | Owned by | Examples |
|---|---|---|
| `gen_ai.*` | OTel GenAI semconv 2026 | `gen_ai.agent.name`, `gen_ai.tokens.input` |
| `forge.run.*` | per-run state (bounded + unbounded) | `forge.run_id`, `forge.run.budget_total_usd` |
| `forge.stage.*` | per-stage state | `forge.stage`, `forge.phase_iterations` |
| `forge.agent.*` | per-dispatch agent state | `forge.agent.tier_used`, `forge.agent.tier_original` |
| `forge.cost.*` | Phase 6 cost governance | `forge.cost.throttle_reason`, `forge.cost.unknown` |
| `forge.batch.*` | review-batch spans | `forge.batch.size`, `forge.batch.agents` |

**Phase 4 rename prerequisite:** Any attributes still emitted as `learning.*` (unprefixed) must be renamed to `forge.learning.*` before Phase 6 merges. Phase 6 will not introduce any new roots outside this table.

## Cardinality budget

Span-name safety — backends meter unique span names. Only **bounded**
attributes may appear in span names.

| Attribute                      | Cardinality | Span-name safe? |
|-------------------------------|-------------|-----------------|
| `gen_ai.agent.name`           | 42 + batches | yes            |
| `gen_ai.request.model`        | pricing-table keyed | yes     |
| `gen_ai.operation.name`       | enum (3)    | yes             |
| `forge.stage`                 | enum (10 + migration) | yes   |
| `forge.mode`                  | enum (4)    | yes             |
| `forge.run_id`                | per-run UUID | **no — attribute only** |
| `gen_ai.agent.id`             | per-invocation UUID | no      |
| `gen_ai.tool.call.id`         | per-call UUID | no            |

Allowed span-name patterns: `pipeline`, `stage.<STAGE>`, `agent.<agent_name>`,
`tool.<tool_name>`, `batch.review-round-<N>`. Nothing else.

## Configuration

```yaml
observability:
  otel:
    enabled: false
    endpoint: "http://localhost:4317"
    exporter: grpc                  # grpc | http | console
    service_name: forge-pipeline
    sample_rate: 1.0
    openinference_compat: false
    include_tool_spans: false
    batch_size: 32
    flush_interval_seconds: 2
```

## OpenInference compatibility

Set `observability.otel.openinference_compat: true` to mirror gen_ai.*
attributes under OpenInference names (`openinference.span.kind=AGENT`,
`llm.token_count.prompt`, `llm.token_count.completion`,
`llm.token_count.total`, `llm.model_name`, `agent.name`) for Arize-heavy
shops. Off by default.

## Migration from `forge-otel-export.sh`

The bash exporter has been deleted. No wrapper, no compatibility
shim. See CHANGELOG.md for rename mapping:

| Old attribute | New attribute               |
|---------------|-----------------------------|
| `tokens_in`   | `gen_ai.tokens.input`       |
| `tokens_out`  | `gen_ai.tokens.output`      |
| `agent`       | `gen_ai.agent.name`         |
| `model`       | `gen_ai.request.model`      |
| `findings_count` | `forge.findings.count`   |

Old config keys removed: `observability.export`,
`observability.otel_endpoint`. Replace with nested `observability.otel.*`.

## Local inspection

Three artefacts are designed to be readable by the shells Forge supports:

| Shell | Current progress | Last 5 runs | Recent hook failures |
|---|---|---|---|
| bash / zsh | `jq . .forge/progress/status.json` | `jq '.runs[0:5]' .forge/run-history-trends.json` | `jq '.recent_hook_failures' .forge/run-history-trends.json` |
| PowerShell | `Get-Content .forge/progress/status.json \| ConvertFrom-Json` | `(Get-Content .forge/run-history-trends.json \| ConvertFrom-Json).runs \| Select-Object -First 5` | `(Get-Content .forge/run-history-trends.json \| ConvertFrom-Json).recent_hook_failures` |
| CMD | `type .forge\progress\status.json` | `type .forge\run-history-trends.json` | (CMD has no JSON parser — use PowerShell or open the file in a text editor) |

**No jq?** Substitute `python3 -m json.tool` for `jq .` (pretty-print) and
`python3 -c "import json,sys; d=json.load(open(sys.argv[1])); ..."` for jq
filter expressions. PowerShell users have `ConvertFrom-Json` built in; CMD
has no JSON parser, so use PowerShell or open the file in a text editor.

The files are atomic-renamed on every update, so a reader that opens them
while they are being rewritten either sees the old copy or the new copy,
never a partial object. Append-only `.forge/.hook-failures.jsonl` lines are
POSIX-atomic when under 4 KB — `stderr_excerpt` is truncated to 2 KB to
stay under that ceiling.

### OTel namespace convention

All forge-emitted OTel span attributes use the `forge.*` root namespace: `forge.run_id`, `forge.stage`, `forge.agent_id`, `forge.finding.dedup_key`, `forge.judge.verdict`, etc. This convention is load-bearing for Phase 6 and Phase 7. Phase 5 adds no new spans — reviewers remain implicit in the pipeline span tree — but the convention is restated here so downstream phases can rely on it.
