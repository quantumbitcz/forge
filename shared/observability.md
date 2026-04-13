# Observability

Defines OTel-style pipeline telemetry for forge runs. Read at PREFLIGHT from `forge-config.md`. Spans emitted on stage transitions and agent dispatches. Retrospective analyzes telemetry for performance patterns.

## Trace Hierarchy

Every pipeline run produces a single trace. Spans nest as follows:

    Pipeline Run (root)
    +-- Stage: PREFLIGHT
    |   +-- Agent: fg-130-docs-discoverer
    |   +-- Agent: fg-140-deprecation-refresh
    +-- Stage: EXPLORING
    |   +-- Agent: fg-100-orchestrator (explore)
    +-- Stage: PLANNING
    |   +-- Agent: fg-200-planner
    +-- Stage: VALIDATING
    |   +-- Agent: fg-210-validator
    +-- Stage: IMPLEMENTING
    |   +-- Agent: fg-300-implementer
    +-- Stage: VERIFYING
    |   +-- Agent: fg-400-quality-gate
    |   +-- Agent: fg-505-build-verifier
    |   +-- Agent: fg-500-test-gate
    +-- Stage: REVIEWING
    |   +-- Batch: review-round-1
    |   |   +-- Agent: fg-410-code-reviewer
    |   |   +-- Agent: fg-411-security-reviewer
    |   |   +-- Agent: fg-412-architecture-reviewer
    |   +-- Batch: review-round-2
    |       +-- Agent: fg-413-frontend-reviewer
    +-- Stage: DOCUMENTING
    |   +-- Agent: fg-350-docs-generator
    +-- Stage: SHIPPING
    |   +-- Agent: fg-590-pre-ship-verifier
    |   +-- Agent: fg-600-pr-builder
    +-- Stage: LEARNING
        +-- Agent: fg-700-retrospective
        +-- Agent: fg-710-post-run

Span types: `pipeline`, `stage`, `agent`, `batch`. Batch spans group parallel agent dispatches (review rounds). Every span carries `start` and `end` timestamps.

## Span Schema

Each span in `telemetry.spans[]`:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Human-readable span name (e.g. `"stage:REVIEWING"`, `"agent:fg-410-code-reviewer"`) |
| `type` | enum | yes | One of: `pipeline`, `stage`, `agent`, `batch` |
| `start` | string | yes | ISO 8601 timestamp |
| `end` | string | yes | ISO 8601 timestamp (set when span closes) |
| `agent` | string | no | Agent ID, present when `type` is `agent` |
| `model` | string | no | Model used for dispatch (e.g. `sonnet`, `opus`) |
| `tokens_in` | integer | no | Input tokens consumed |
| `tokens_out` | integer | no | Output tokens produced |
| `findings_count` | integer | no | Number of findings emitted by this agent |

Spans are append-only. The orchestrator opens a span before dispatch and closes it on return.

## Metrics

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `forge.stage.duration_seconds` | histogram | `stage` | Wall-clock duration of each pipeline stage |
| `forge.agent.duration_seconds` | histogram | `agent` | Wall-clock duration of each agent dispatch |
| `forge.agent.tokens.input` | counter | `agent`, `model` | Cumulative input tokens per agent |
| `forge.agent.tokens.output` | counter | `agent`, `model` | Cumulative output tokens per agent |
| `forge.convergence.iterations` | gauge | `phase` | Current iteration count per convergence phase |
| `forge.score` | gauge | `component` | Latest quality score |
| `forge.findings.count` | counter | `category`, `severity` | Finding count bucketed by category and severity |
| `forge.recovery.budget_used` | gauge | | Current recovery budget weight consumed |
| `forge.model.distribution` | histogram | `model` | Distribution of model tiers across dispatches |

Metrics are updated in-place in `telemetry.metrics{}`. Counter values are monotonically increasing within a run. Gauges reflect current state.

## Configuration

In `forge-config.md`:

    observability:
      enabled: true
      export: local
      otel_endpoint: ""
      trace_all_agents: true
      metrics_in_recap: true

| Parameter | Valid Values | Default | Description |
|-----------|-------------|---------|-------------|
| `observability.enabled` | `true`, `false` | `true` | Master switch for telemetry collection |
| `observability.export` | `local`, `otel` | `local` | Export mode |
| `observability.otel_endpoint` | URL string | `""` | OTel collector endpoint (required when `export: otel`) |
| `observability.trace_all_agents` | `true`, `false` | `true` | When false, only stage-level spans are emitted |
| `observability.metrics_in_recap` | `true`, `false` | `true` | Include telemetry summary in post-run recap |

When `observability.enabled` is `false`, no spans or metrics are collected. Agents run normally without instrumentation overhead.

## Export Modes

### Local (default)

Telemetry stored in `state.json.telemetry`. No external dependencies. Available for retrospective analysis and `/forge-profile`.

    {
      "telemetry": {
        "spans": [ ... ],
        "metrics": { ... },
        "export_status": "pending"
      }
    }

### OTel

Exports telemetry as HTTP/JSON to an OTel collector via `forge-otel-export.sh`. The script runs at LEARNING after all spans are closed:

1. Reads `state.json.telemetry`
2. Converts spans to OTel-compatible JSON (trace/span format)
3. POSTs to `observability.otel_endpoint`
4. Updates `export_status` to `exported` or `failed`

Export failures are non-fatal. A WARNING is logged and `export_status` set to `failed`. The pipeline does not retry exports.

## State Schema

The `telemetry` object in `state.json`:

| Field | Type | Description |
|-------|------|-------------|
| `telemetry.spans` | array | Append-only list of span objects |
| `telemetry.metrics` | object | Metric name to current value mapping |
| `telemetry.export_status` | enum | One of: `pending`, `exported`, `failed` |

Initial state (set at PREFLIGHT when `observability.enabled`):

    {
      "telemetry": {
        "spans": [],
        "metrics": {},
        "export_status": "pending"
      }
    }

## PREFLIGHT Constraints

Validated at PREFLIGHT. If violated, log WARNING and use plugin defaults:

| Parameter | Constraint | Default |
|-----------|-----------|---------|
| `observability.enabled` | `true` or `false` | `true` |
| `observability.export` | `local` or `otel` | `local` |
| `observability.otel_endpoint` | Non-empty string when `export: otel` | `""` |
| `observability.trace_all_agents` | `true` or `false` | `true` |
| `observability.metrics_in_recap` | `true` or `false` | `true` |

If `export` is `otel` and `otel_endpoint` is empty, PREFLIGHT logs WARNING and falls back to `local`.

## Orchestrator Integration

The orchestrator emits telemetry at two points:

1. **Stage transitions** — opens a `stage` span when entering a stage, closes it on exit. Duration recorded as `forge.stage.duration_seconds`.
2. **Agent dispatches** — opens an `agent` span before `Agent(...)`, closes on return. Captures `model`, `tokens_in`, `tokens_out`, `findings_count`. Duration recorded as `forge.agent.duration_seconds`.

When `trace_all_agents` is `false`, agent-level spans are skipped. Stage spans are always emitted.

Batch spans wrap parallel review dispatches. The quality gate opens a `batch` span, dispatches reviewers, and closes the batch when all return.

## Retrospective Integration

`fg-700-retrospective` reads `telemetry.spans[]` and `telemetry.metrics{}` to identify:

- **Slowest stages** — stages with duration above 2x the median
- **Token-heavy agents** — agents consuming disproportionate input tokens relative to output quality
- **Convergence cost** — total iterations and tokens spent in verify/review loops
- **Model efficiency** — whether premium-tier agents justified their cost via finding quality

Retrospective findings are recorded in `stage_9_notes` under `## Telemetry Analysis`. At most 3 telemetry-derived suggestions per run.

## Post-Run Integration

When `metrics_in_recap` is `true`, `fg-710-post-run` includes a telemetry summary in the run recap:

    ## Telemetry
    - Total duration: 4m 32s
    - Stages: 10 completed
    - Agent dispatches: 18
    - Total tokens: 45,200 in / 12,800 out
    - Slowest stage: REVIEWING (1m 15s)
    - Export: local (pending)

When `metrics_in_recap` is `false`, the telemetry section is omitted from the recap.
