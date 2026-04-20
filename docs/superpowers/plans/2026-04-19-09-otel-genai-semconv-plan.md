# Phase 09 — OpenTelemetry GenAI Semconv Emission — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `shared/forge-otel-export.sh` with a Python-native OpenTelemetry GenAI 2026 semconv emitter at `hooks/_py/otel.py` that streams pipeline/stage/agent spans live with W3C Trace Context propagation.

**Architecture:** Event-sourced emitter tails `.forge/events.jsonl` (Phase F07) and translates rows to OTel spans. `ParentBased(TraceIdRatioBased)` sampler keeps child trace decisions aligned with the root. W3C `TRACEPARENT` env var propagates context to subagent dispatches. `BatchSpanProcessor` flushes live (best-effort); `replay()` is the authoritative recovery path for crashed runs.

**Tech Stack:** Python 3.10+, `opentelemetry-api/sdk/exporter-otlp >= 1.30.0`, pytest, GitHub Actions, Docker (`otel/opentelemetry-collector-contrib:0.105.0`).

**Dependency:** Phase 02 (Cross-Platform Python Hooks) MUST be merged first — this plan imports from `hooks/_py/` and treats Python hooks as the default path. **Merge-gated.** Do not merge this PR before Phase 02.

---

## Review Issue Resolutions (from spec review APPROVE WITH MINOR)

| # | Issue | Resolution in this plan |
|---|-------|-------------------------|
| 1 | §3.7 "partial telemetry on crash" contradicts §10's 2s loss window | Task 2 sets `replay()` as authoritative recovery; Task 14 documents best-effort live stream + replay contract. Live flush is advisory, not durable. |
| 2 | `sample_rate` lacks sampler type | Task 3 wires `ParentBased(root=TraceIdRatioBased(sample_rate))` exclusively; Task 4 respects inbound `TRACEPARENT` sampled=0. Child spans always follow root decision. |
| 3 | Cardinality budget unstated | Task 1 adds explicit `BOUNDED_ATTRS` vs `UNBOUNDED_ATTRS` lists in `otel_attributes.py`; Task 14 documents `forge.run_id` as attribute-only (never span name). Span names use only bounded values. |

---

## File Structure

### New files
| Path | Responsibility |
|---|---|
| `hooks/_py/otel.py` | Public API: `init`, `shutdown`, `stage_span`, `agent_span`, `tool_span`, `record_agent_result`, `replay`, `pipeline_span` |
| `hooks/_py/otel_attributes.py` | Frozen string constants for every semconv attribute; `BOUNDED_ATTRS`/`UNBOUNDED_ATTRS` cardinality lists |
| `hooks/_py/otel_exporters.py` | Exporter factory keyed on `grpc`/`http`/`console` |
| `hooks/_py/otel_context.py` | W3C `TRACEPARENT`/`TRACESTATE` propagation helpers + `ParentBased` sampler construction |
| `hooks/_py/event_to_span.py` | Translator: `.forge/events.jsonl` row → span open/close operations |
| `hooks/_py/otel_cli.py` | CLI entry: `python -m hooks._py.otel_cli replay --from-events <path>` |
| `shared/schemas/otel-genai-v1.json` | Pinned local copy of OTel GenAI semconv JSON Schema |
| `tests/python/test_otel_attributes.py` | Unit test: attribute name constants match semconv |
| `tests/python/test_otel_context.py` | Unit test: TRACEPARENT extract/inject round-trip |
| `tests/python/test_event_to_span.py` | Unit test: event→span translator parity |
| `tests/python/test_otel_sampler.py` | Unit test: `ParentBased` decision propagation |
| `tests/python/test_otel_replay.py` | Unit test: replay determinism (same events → same spans modulo timing) |
| `tests/python/test_otel_cardinality.py` | Unit test: span names contain only bounded values |
| `tests/python/otel_semconv_validator.py` | CI validator: schema + hierarchy + trace-id propagation |
| `tests/fixtures/events-sample.jsonl` | Fixture: canonical event log for replay tests |
| `.github/workflows/phase09-otel.yml` | CI jobs: `otel-semconv-validation`, `otel-replay`, `otel-disabled-overhead` |

### Modified files
| Path | Change |
|---|---|
| `shared/observability.md` | Rewrite: semconv attributes, `observability.otel.*` config, replay as authoritative, cardinality budget |
| `agents/fg-100-orchestrator.md` | Add `otel.pipeline_span`/`otel.stage_span`/`otel.agent_span` wrappers; document `TRACEPARENT` env-var contract for Task dispatches |
| `shared/preflight-constraints.md` | Add `observability.otel.*` validation table |
| `plugin.json` | Declare optional `[otel]` extra |
| `CHANGELOG.md` | Breaking-change notice: config migration, attribute rename, bash exporter removal |

### Deleted files
| Path | Reason |
|---|---|
| `shared/forge-otel-export.sh` | Replaced wholesale by `otel.replay()` |

---

## Task Decomposition

18 tasks. Each commits using Conventional Commits format. Tasks 1–10 build the emitter bottom-up (TDD). Tasks 11–14 wire integration points. Tasks 15–17 add CI + docs. Task 18 deletes the legacy bash exporter and bumps version.

---

### Task 1: Semconv attribute constants + cardinality budget

**Files:**
- Create: `hooks/_py/otel_attributes.py`
- Test: `tests/python/test_otel_attributes.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/python/test_otel_attributes.py
from hooks._py import otel_attributes as attrs


def test_gen_ai_attribute_names_match_semconv():
    assert attrs.GEN_AI_AGENT_NAME == "gen_ai.agent.name"
    assert attrs.GEN_AI_AGENT_DESCRIPTION == "gen_ai.agent.description"
    assert attrs.GEN_AI_AGENT_ID == "gen_ai.agent.id"
    assert attrs.GEN_AI_OPERATION_NAME == "gen_ai.operation.name"
    assert attrs.GEN_AI_REQUEST_MODEL == "gen_ai.request.model"
    assert attrs.GEN_AI_TOKENS_INPUT == "gen_ai.tokens.input"
    assert attrs.GEN_AI_TOKENS_OUTPUT == "gen_ai.tokens.output"
    assert attrs.GEN_AI_TOKENS_TOTAL == "gen_ai.tokens.total"
    assert attrs.GEN_AI_COST_USD == "gen_ai.cost.usd"
    assert attrs.GEN_AI_TOOL_CALLS == "gen_ai.tool.calls"
    assert attrs.GEN_AI_RESPONSE_FINISH_REASONS == "gen_ai.response.finish_reasons"
    assert attrs.OP_INVOKE_AGENT == "invoke_agent"
    assert attrs.OP_EXECUTE_TOOL == "execute_tool"


def test_forge_attribute_names():
    assert attrs.FORGE_RUN_ID == "forge.run_id"
    assert attrs.FORGE_STAGE == "forge.stage"
    assert attrs.FORGE_MODE == "forge.mode"
    assert attrs.FORGE_SCORE == "forge.score"


def test_cardinality_lists_are_disjoint_and_complete():
    # Every forge.* / gen_ai.* attribute must be classified.
    bounded = set(attrs.BOUNDED_ATTRS)
    unbounded = set(attrs.UNBOUNDED_ATTRS)
    assert bounded.isdisjoint(unbounded)
    # run_id is attribute-only, never a span name.
    assert attrs.FORGE_RUN_ID in unbounded
    # agent name + stage + mode are low cardinality, safe for names.
    assert attrs.GEN_AI_AGENT_NAME in bounded
    assert attrs.FORGE_STAGE in bounded
    assert attrs.FORGE_MODE in bounded
    # tool call id and agent id are per-invocation -> unbounded.
    assert attrs.GEN_AI_TOOL_CALL_ID in unbounded
    assert attrs.GEN_AI_AGENT_ID in unbounded
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/python/test_otel_attributes.py -v`
Expected: FAIL — `ModuleNotFoundError: hooks._py.otel_attributes`.

- [ ] **Step 3: Write minimal implementation**

```python
# hooks/_py/otel_attributes.py
"""Frozen semconv attribute names + cardinality budget.

Single source of truth. Do NOT inline attribute strings elsewhere.

Cardinality budget (span-name safety):
  BOUNDED_ATTRS   -- safe to interpolate into span names (low cardinality,
                     stable membership). Backends like Tempo/Honeycomb meter
                     unique span names; keep this list small.
  UNBOUNDED_ATTRS -- attribute-only; NEVER include in span names.
"""
from __future__ import annotations

# gen_ai.* (OTel GenAI semconv 2026)
GEN_AI_AGENT_NAME = "gen_ai.agent.name"
GEN_AI_AGENT_DESCRIPTION = "gen_ai.agent.description"
GEN_AI_AGENT_ID = "gen_ai.agent.id"
GEN_AI_OPERATION_NAME = "gen_ai.operation.name"
GEN_AI_REQUEST_MODEL = "gen_ai.request.model"
GEN_AI_TOKENS_INPUT = "gen_ai.tokens.input"
GEN_AI_TOKENS_OUTPUT = "gen_ai.tokens.output"
GEN_AI_TOKENS_TOTAL = "gen_ai.tokens.total"
GEN_AI_COST_USD = "gen_ai.cost.usd"
GEN_AI_TOOL_CALLS = "gen_ai.tool.calls"
GEN_AI_TOOL_NAME = "gen_ai.tool.name"
GEN_AI_TOOL_CALL_ID = "gen_ai.tool.call.id"
GEN_AI_RESPONSE_FINISH_REASONS = "gen_ai.response.finish_reasons"

# gen_ai.operation.name enum
OP_INVOKE_AGENT = "invoke_agent"
OP_EXECUTE_TOOL = "execute_tool"
OP_CREATE_AGENT = "create_agent"

# forge.* (forge-specific; not semconv)
FORGE_RUN_ID = "forge.run_id"
FORGE_STAGE = "forge.stage"
FORGE_MODE = "forge.mode"
FORGE_SCORE = "forge.score"
FORGE_PHASE_ITERATIONS = "forge.phase_iterations"
FORGE_CONVERGENCE_ITERATIONS = "forge.convergence.iterations"
FORGE_BATCH_SIZE = "forge.batch.size"
FORGE_BATCH_AGENTS = "forge.batch.agents"
FORGE_COST_UNKNOWN = "forge.cost.unknown"

# Cardinality budget.
BOUNDED_ATTRS: tuple[str, ...] = (
    GEN_AI_AGENT_NAME,       # 42 agents + review-batch-<N>, bounded.
    GEN_AI_REQUEST_MODEL,    # pricing-table keyed, bounded.
    GEN_AI_OPERATION_NAME,   # enum: invoke_agent|execute_tool|create_agent.
    FORGE_STAGE,             # 10 pipeline stages + migration sub-states.
    FORGE_MODE,              # enum: standard|bugfix|migration|bootstrap.
)

UNBOUNDED_ATTRS: tuple[str, ...] = (
    FORGE_RUN_ID,            # per-run UUID. ATTRIBUTE ONLY. Never a span name.
    GEN_AI_AGENT_ID,         # per-invocation UUID.
    GEN_AI_TOOL_CALL_ID,     # per-call UUID.
    FORGE_SCORE,             # numeric, not a span-name component.
    FORGE_PHASE_ITERATIONS,
    FORGE_CONVERGENCE_ITERATIONS,
    FORGE_BATCH_SIZE,
    GEN_AI_TOKENS_INPUT,
    GEN_AI_TOKENS_OUTPUT,
    GEN_AI_TOKENS_TOTAL,
    GEN_AI_COST_USD,
    GEN_AI_TOOL_CALLS,
)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/python/test_otel_attributes.py -v`
Expected: PASS — 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/otel_attributes.py tests/python/test_otel_attributes.py
git commit -m "feat(phase09): add OTel GenAI semconv attribute constants + cardinality budget"
```

---

### Task 2: Public API surface (no-op skeleton + `replay` as authoritative recovery)

**Files:**
- Create: `hooks/_py/otel.py`
- Test: `tests/python/test_otel_noop.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/python/test_otel_noop.py
from hooks._py import otel


def test_init_disabled_is_noop(tmp_path):
    state = otel.init({"enabled": False})
    assert state.enabled is False
    # All calls must be safe when disabled.
    with otel.pipeline_span(run_id="r1", mode="standard"):
        with otel.stage_span("EXPLORING"):
            with otel.agent_span(name="fg-100-orchestrator", model="sonnet",
                                  description="orchestrator"):
                otel.record_agent_result({"tokens_input": 1, "tokens_output": 2,
                                            "cost_usd": 0.01, "tool_calls": 0})
    otel.shutdown()


def test_replay_is_documented_as_authoritative(tmp_path):
    # replay() exists, accepts events.jsonl path, is the authoritative
    # recovery path (the live stream is best-effort).
    events = tmp_path / "events.jsonl"
    events.write_text("")  # empty file
    # Disabled config -> no-op replay must not raise and must return 0.
    n = otel.replay(events_path=str(events), config={"enabled": False})
    assert n == 0
    assert "authoritative" in (otel.replay.__doc__ or "").lower()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/python/test_otel_noop.py -v`
Expected: FAIL — `ModuleNotFoundError: hooks._py.otel`.

- [ ] **Step 3: Write minimal implementation**

```python
# hooks/_py/otel.py
"""Public OTel GenAI semconv emitter.

Durability contract:
  - Live stream is BEST-EFFORT. `BatchSpanProcessor` flushes every
    `flush_interval_seconds` or when `batch_size` is reached. A hard crash
    (SIGKILL, OOM, power loss) drops the in-memory batch.
  - `replay()` is the AUTHORITATIVE recovery path. It rebuilds spans from
    `.forge/events.jsonl` and re-emits them deterministically. Event log
    writes are fsync'd by Phase F07 (`state_write.py`), so replay is the
    source of truth. Schedule `replay` in CI failure handlers.
"""
from __future__ import annotations

import contextlib
import dataclasses
import os
from typing import Any, Iterator


@dataclasses.dataclass
class EmitterState:
    enabled: bool = False
    tracer: Any = None
    provider: Any = None


_STATE = EmitterState()


def init(config: dict, parent_traceparent: str | None = None) -> EmitterState:
    """Initialise emitter. Returns a no-op state when disabled or on import error."""
    global _STATE
    if not config.get("enabled", False):
        _STATE = EmitterState(enabled=False)
        return _STATE
    # Real init wired in Task 3.
    _STATE = EmitterState(enabled=False)
    return _STATE


def shutdown() -> None:
    """Flush pending spans and tear down the provider."""
    if _STATE.provider is not None:
        _STATE.provider.shutdown()


@contextlib.contextmanager
def pipeline_span(*, run_id: str, mode: str) -> Iterator[Any]:
    yield None


@contextlib.contextmanager
def stage_span(name: str) -> Iterator[Any]:
    yield None


@contextlib.contextmanager
def agent_span(*, name: str, model: str, description: str) -> Iterator[Any]:
    yield None


@contextlib.contextmanager
def tool_span(*, name: str, call_id: str | None = None) -> Iterator[Any]:
    yield None


def record_agent_result(result: dict) -> None:
    """No-op when disabled. Real impl in Task 5."""
    return None


def replay(*, events_path: str, config: dict) -> int:
    """Authoritative recovery path.

    Rebuilds spans from the event-sourced log (`.forge/events.jsonl`) and
    exports them via the configured exporter. Use this when a run crashed
    before the live stream flushed — the event log is fsync'd and is the
    source of truth. Returns the number of spans emitted.
    """
    if not config.get("enabled", False):
        return 0
    # Real impl in Task 10.
    return 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/python/test_otel_noop.py -v`
Expected: PASS — 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/otel.py tests/python/test_otel_noop.py
git commit -m "feat(phase09): add otel public API skeleton with no-op fallback"
```

---

### Task 3: Exporter factory + `ParentBased(TraceIdRatioBased)` sampler

**Files:**
- Create: `hooks/_py/otel_exporters.py`
- Create: `hooks/_py/otel_context.py` (sampler construction only; propagation in Task 4)
- Test: `tests/python/test_otel_sampler.py`
- Test: `tests/python/test_otel_exporters.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/python/test_otel_sampler.py
import pytest
pytest.importorskip("opentelemetry.sdk.trace.sampling")

from opentelemetry.sdk.trace.sampling import ParentBased, TraceIdRatioBased
from hooks._py.otel_context import build_sampler


def test_sampler_is_parent_based_with_ratio_root():
    s = build_sampler(sample_rate=0.25)
    assert isinstance(s, ParentBased)
    # Root delegate must be ratio-based with the exact rate.
    assert isinstance(s._root, TraceIdRatioBased)  # noqa: SLF001
    # Descriptive text is stable enough to assert the ratio.
    assert "0.25" in s.get_description() or "0.250000" in s.get_description()


def test_sample_rate_1_0_samples_all_roots():
    s = build_sampler(sample_rate=1.0)
    assert isinstance(s, ParentBased)


def test_sample_rate_0_0_samples_no_roots():
    s = build_sampler(sample_rate=0.0)
    assert isinstance(s, ParentBased)


@pytest.mark.parametrize("bad", [-0.1, 1.1, "half", None])
def test_invalid_sample_rate_raises(bad):
    with pytest.raises((ValueError, TypeError)):
        build_sampler(sample_rate=bad)
```

```python
# tests/python/test_otel_exporters.py
import pytest
pytest.importorskip("opentelemetry.exporter.otlp.proto.grpc.trace_exporter")

from hooks._py.otel_exporters import build_exporter


def test_grpc_exporter():
    e = build_exporter(kind="grpc", endpoint="http://localhost:4317")
    assert type(e).__name__ == "OTLPSpanExporter"


def test_http_exporter():
    e = build_exporter(kind="http", endpoint="http://localhost:4318/v1/traces")
    assert type(e).__name__ == "OTLPSpanExporter"


def test_console_exporter():
    e = build_exporter(kind="console", endpoint="")
    assert type(e).__name__ == "ConsoleSpanExporter"


def test_unknown_exporter_raises():
    with pytest.raises(ValueError, match="exporter"):
        build_exporter(kind="kafka", endpoint="")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/python/test_otel_sampler.py tests/python/test_otel_exporters.py -v`
Expected: FAIL — `ModuleNotFoundError: hooks._py.otel_context` / `hooks._py.otel_exporters`.

- [ ] **Step 3: Write minimal implementation**

```python
# hooks/_py/otel_context.py
"""W3C trace-context helpers + sampler factory.

Sampler: ParentBased(TraceIdRatioBased(sample_rate)).

Why ParentBased? With distributed tracing (TRACEPARENT propagation to
subagents), each child process must honour the root decision. Otherwise
children make independent sampling decisions and produce orphan partial
traces, breaking Phase 09 success criterion 3 ("every subagent span shares
the pipeline's trace_id").
"""
from __future__ import annotations

from opentelemetry.sdk.trace.sampling import (
    ALWAYS_OFF,
    ALWAYS_ON,
    ParentBased,
    Sampler,
    TraceIdRatioBased,
)


def build_sampler(*, sample_rate: float) -> Sampler:
    """Return a ParentBased sampler honouring the configured root rate."""
    if not isinstance(sample_rate, (int, float)) or isinstance(sample_rate, bool):
        raise TypeError(f"sample_rate must be a number, got {type(sample_rate).__name__}")
    if not 0.0 <= float(sample_rate) <= 1.0:
        raise ValueError(f"sample_rate must be in [0.0, 1.0], got {sample_rate}")
    rate = float(sample_rate)
    if rate == 1.0:
        root: Sampler = ALWAYS_ON
    elif rate == 0.0:
        root = ALWAYS_OFF
    else:
        root = TraceIdRatioBased(rate)
    return ParentBased(root=root)
```

```python
# hooks/_py/otel_exporters.py
"""Exporter factory keyed on config.observability.otel.exporter."""
from __future__ import annotations

from typing import Any


def build_exporter(*, kind: str, endpoint: str, headers: dict[str, str] | None = None) -> Any:
    if kind == "grpc":
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
        return OTLPSpanExporter(endpoint=endpoint, headers=headers or {})
    if kind == "http":
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
        return OTLPSpanExporter(endpoint=endpoint, headers=headers or {})
    if kind == "console":
        from opentelemetry.sdk.trace.export import ConsoleSpanExporter
        return ConsoleSpanExporter()
    raise ValueError(f"unknown exporter kind: {kind!r} (expected grpc|http|console)")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/python/test_otel_sampler.py tests/python/test_otel_exporters.py -v`
Expected: PASS — 8 tests pass (or skip if `opentelemetry` not installed locally; CI runs it).

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/otel_context.py hooks/_py/otel_exporters.py tests/python/test_otel_sampler.py tests/python/test_otel_exporters.py
git commit -m "feat(phase09): add ParentBased(TraceIdRatioBased) sampler + exporter factory"
```

---

### Task 4: W3C TRACEPARENT env-var propagation

**Files:**
- Modify: `hooks/_py/otel_context.py`
- Test: `tests/python/test_otel_context.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/python/test_otel_context.py
import os
import pytest
pytest.importorskip("opentelemetry.trace")

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.sampling import ALWAYS_ON

from hooks._py.otel_context import (
    inject_traceparent_env,
    extract_parent_from_env,
    TRACEPARENT_ENV,
)


def _provider():
    return TracerProvider(sampler=ALWAYS_ON)


def test_inject_sets_traceparent_env(monkeypatch):
    monkeypatch.delenv(TRACEPARENT_ENV, raising=False)
    p = _provider()
    trace.set_tracer_provider(p)
    tracer = p.get_tracer("t")
    with tracer.start_as_current_span("root") as span:
        env: dict[str, str] = {}
        inject_traceparent_env(env)
        assert TRACEPARENT_ENV in env
        tp = env[TRACEPARENT_ENV]
        # W3C format: {version}-{trace_id:32}-{span_id:16}-{flags:2}
        parts = tp.split("-")
        assert len(parts) == 4
        assert parts[0] == "00"
        assert len(parts[1]) == 32
        assert len(parts[2]) == 16
        assert len(parts[3]) == 2
        # trace_id matches active span
        ctx = span.get_span_context()
        assert parts[1] == format(ctx.trace_id, "032x")


def test_extract_rehydrates_parent(monkeypatch):
    tp = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    monkeypatch.setenv(TRACEPARENT_ENV, tp)
    ctx = extract_parent_from_env()
    assert ctx is not None
    span = trace.get_current_span(ctx)
    sc = span.get_span_context()
    assert format(sc.trace_id, "032x") == "4bf92f3577b34da6a3ce929d0e0e4736"
    assert format(sc.span_id, "016x") == "00f067aa0ba902b7"
    assert sc.trace_flags == 0x01


def test_extract_respects_sampled_zero(monkeypatch):
    # Inbound parent with sampled=0 -> child must propagate that decision.
    tp = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
    monkeypatch.setenv(TRACEPARENT_ENV, tp)
    ctx = extract_parent_from_env()
    sc = trace.get_current_span(ctx).get_span_context()
    assert sc.trace_flags == 0x00


def test_extract_missing_env_returns_none(monkeypatch):
    monkeypatch.delenv(TRACEPARENT_ENV, raising=False)
    assert extract_parent_from_env() is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/python/test_otel_context.py -v`
Expected: FAIL — `ImportError: cannot import name 'inject_traceparent_env'`.

- [ ] **Step 3: Write minimal implementation**

Append to `hooks/_py/otel_context.py`:

```python
# --- W3C Trace Context propagation ----------------------------------------
from opentelemetry import context as _otel_context
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

TRACEPARENT_ENV = "TRACEPARENT"
TRACESTATE_ENV = "TRACESTATE"

_PROPAGATOR = TraceContextTextMapPropagator()


def inject_traceparent_env(env: dict[str, str]) -> None:
    """Serialize the active span context into the given env dict.

    Called before dispatching a subagent via the Task tool. The Task tool
    inherits parent env, so writing `TRACEPARENT` into the child env is
    sufficient for propagation.
    """
    _PROPAGATOR.inject(env)  # writes 'traceparent' (lowercase) per W3C
    # Promote to uppercase env-var form expected by subagent init.
    if "traceparent" in env:
        env[TRACEPARENT_ENV] = env.pop("traceparent")
    if "tracestate" in env:
        env[TRACESTATE_ENV] = env.pop("tracestate")


def extract_parent_from_env():
    """Rehydrate a parent span context from TRACEPARENT in the environment.

    Returns None when the env var is absent. The returned Context must be
    passed to `TracerProvider.get_tracer(...).start_as_current_span(ctx=...)`
    so the first local span becomes a child of the external parent.

    Respects sampled=0 in the inbound traceparent: when the parent was not
    sampled, the ParentBased sampler yields a non-recording span in the
    child, which is the correct behaviour for distributed tracing.
    """
    import os as _os
    tp = _os.environ.get(TRACEPARENT_ENV)
    if not tp:
        return None
    carrier = {"traceparent": tp}
    ts = _os.environ.get(TRACESTATE_ENV)
    if ts:
        carrier["tracestate"] = ts
    return _PROPAGATOR.extract(carrier)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/python/test_otel_context.py -v`
Expected: PASS — 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/otel_context.py tests/python/test_otel_context.py
git commit -m "feat(phase09): add W3C TRACEPARENT env-var injection + extraction"
```

---

### Task 5: Wire `init`/`shutdown` + real span emission in `otel.py`

**Files:**
- Modify: `hooks/_py/otel.py`
- Test: `tests/python/test_otel_emission.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/python/test_otel_emission.py
import pytest
pytest.importorskip("opentelemetry.sdk.trace")

from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter
from opentelemetry.sdk.trace.export import SimpleSpanProcessor

from hooks._py import otel
from hooks._py import otel_attributes as A


def _enable_with_memory_exporter(monkeypatch):
    exporter = InMemorySpanExporter()
    monkeypatch.setattr(otel, "_build_processor",
                        lambda cfg: SimpleSpanProcessor(exporter), raising=False)
    otel.init({"enabled": True, "service_name": "forge-pipeline",
               "sample_rate": 1.0, "exporter": "console",
               "endpoint": "", "batch_size": 1, "flush_interval_seconds": 1})
    return exporter


def test_pipeline_span_attributes(monkeypatch):
    exporter = _enable_with_memory_exporter(monkeypatch)
    with otel.pipeline_span(run_id="run-abc", mode="standard"):
        pass
    otel.shutdown()
    spans = exporter.get_finished_spans()
    assert len(spans) == 1
    s = spans[0]
    assert s.name == "pipeline"
    assert s.attributes[A.GEN_AI_AGENT_NAME] == "forge-pipeline"
    assert s.attributes[A.GEN_AI_OPERATION_NAME] == A.OP_INVOKE_AGENT
    assert s.attributes[A.FORGE_RUN_ID] == "run-abc"
    assert s.attributes[A.FORGE_MODE] == "standard"


def test_nested_stage_and_agent_spans(monkeypatch):
    exporter = _enable_with_memory_exporter(monkeypatch)
    with otel.pipeline_span(run_id="r1", mode="standard"):
        with otel.stage_span("EXPLORING"):
            with otel.agent_span(name="fg-100-orchestrator",
                                  model="claude-sonnet-4-7",
                                  description="Coordinator"):
                otel.record_agent_result({
                    "tokens_input": 100, "tokens_output": 200,
                    "cost_usd": 0.005, "tool_calls": 3,
                    "finish_reasons": ["stop"],
                })
    otel.shutdown()
    by_name = {s.name: s for s in exporter.get_finished_spans()}
    assert set(by_name) == {"pipeline", "stage.EXPLORING", "agent.fg-100-orchestrator"}
    a = by_name["agent.fg-100-orchestrator"]
    assert a.attributes[A.GEN_AI_AGENT_NAME] == "fg-100-orchestrator"
    assert a.attributes[A.GEN_AI_REQUEST_MODEL] == "claude-sonnet-4-7"
    assert a.attributes[A.GEN_AI_TOKENS_INPUT] == 100
    assert a.attributes[A.GEN_AI_TOKENS_OUTPUT] == 200
    assert a.attributes[A.GEN_AI_TOKENS_TOTAL] == 300
    assert a.attributes[A.GEN_AI_COST_USD] == 0.005
    assert a.attributes[A.GEN_AI_TOOL_CALLS] == 3
    # Parent/child hierarchy: all three share trace_id; agent -> stage -> pipeline.
    trace_ids = {s.context.trace_id for s in exporter.get_finished_spans()}
    assert len(trace_ids) == 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/python/test_otel_emission.py -v`
Expected: FAIL — pipeline span not emitted / attributes missing.

- [ ] **Step 3: Write minimal implementation**

Replace body of `hooks/_py/otel.py`:

```python
# hooks/_py/otel.py
"""Public OTel GenAI semconv emitter.

Durability contract:
  - Live stream is BEST-EFFORT. BatchSpanProcessor flushes every
    `flush_interval_seconds` or when `batch_size` is reached. A hard crash
    drops the in-memory batch.
  - `replay()` is the AUTHORITATIVE recovery path — rebuilds from the
    fsync'd event log.
"""
from __future__ import annotations

import contextlib
import dataclasses
import logging
import threading
from typing import Any, Iterator

from hooks._py import otel_attributes as A

log = logging.getLogger(__name__)


@dataclasses.dataclass
class EmitterState:
    enabled: bool = False
    tracer: Any = None
    provider: Any = None
    cfg: dict = dataclasses.field(default_factory=dict)


_STATE = EmitterState()
_LOCK = threading.Lock()
_TOTAL_RESULT: dict[int, dict] = {}  # span_id -> pending result, set by record_agent_result


def _build_processor(cfg: dict):
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from hooks._py.otel_exporters import build_exporter
    exporter = build_exporter(kind=cfg.get("exporter", "grpc"),
                               endpoint=cfg.get("endpoint", ""))
    return BatchSpanProcessor(
        exporter,
        max_export_batch_size=int(cfg.get("batch_size", 32)),
        schedule_delay_millis=int(float(cfg.get("flush_interval_seconds", 2)) * 1000),
    )


def init(config: dict, parent_traceparent: str | None = None) -> EmitterState:
    global _STATE
    with _LOCK:
        if not config.get("enabled", False):
            _STATE = EmitterState(enabled=False, cfg=config)
            return _STATE
        try:
            from opentelemetry import trace
            from opentelemetry.sdk.resources import Resource, SERVICE_NAME
            from opentelemetry.sdk.trace import TracerProvider
            from hooks._py.otel_context import build_sampler
        except ImportError:
            log.warning("opentelemetry not installed — OTel export disabled")
            _STATE = EmitterState(enabled=False, cfg=config)
            return _STATE

        resource = Resource.create({SERVICE_NAME: config.get("service_name",
                                                               "forge-pipeline")})
        sampler = build_sampler(sample_rate=float(config.get("sample_rate", 1.0)))
        provider = TracerProvider(resource=resource, sampler=sampler)
        provider.add_span_processor(_build_processor(config))
        trace.set_tracer_provider(provider)
        tracer = provider.get_tracer("forge.pipeline")
        _STATE = EmitterState(enabled=True, tracer=tracer, provider=provider, cfg=config)
        return _STATE


def shutdown() -> None:
    with _LOCK:
        if _STATE.provider is not None:
            _STATE.provider.shutdown()


def _noop_cm() -> Iterator[Any]:
    yield None


@contextlib.contextmanager
def pipeline_span(*, run_id: str, mode: str) -> Iterator[Any]:
    if not _STATE.enabled:
        yield None
        return
    with _STATE.tracer.start_as_current_span("pipeline") as span:
        span.set_attribute(A.GEN_AI_AGENT_NAME, "forge-pipeline")
        span.set_attribute(A.GEN_AI_OPERATION_NAME, A.OP_INVOKE_AGENT)
        span.set_attribute(A.FORGE_RUN_ID, run_id)
        span.set_attribute(A.FORGE_MODE, mode)
        yield span


@contextlib.contextmanager
def stage_span(name: str) -> Iterator[Any]:
    if not _STATE.enabled:
        yield None
        return
    with _STATE.tracer.start_as_current_span(f"stage.{name}") as span:
        span.set_attribute(A.FORGE_STAGE, name)
        yield span


@contextlib.contextmanager
def agent_span(*, name: str, model: str, description: str) -> Iterator[Any]:
    if not _STATE.enabled:
        yield None
        return
    with _STATE.tracer.start_as_current_span(f"agent.{name}") as span:
        span.set_attribute(A.GEN_AI_AGENT_NAME, name)
        span.set_attribute(A.GEN_AI_AGENT_DESCRIPTION, description)
        span.set_attribute(A.GEN_AI_OPERATION_NAME, A.OP_INVOKE_AGENT)
        span.set_attribute(A.GEN_AI_REQUEST_MODEL, model)
        _TOTAL_RESULT[span.get_span_context().span_id] = {}
        try:
            yield span
        finally:
            result = _TOTAL_RESULT.pop(span.get_span_context().span_id, {})
            if result:
                _apply_agent_result(span, result)


def _apply_agent_result(span: Any, r: dict) -> None:
    ti = int(r.get("tokens_input", 0))
    to = int(r.get("tokens_output", 0))
    span.set_attribute(A.GEN_AI_TOKENS_INPUT, ti)
    span.set_attribute(A.GEN_AI_TOKENS_OUTPUT, to)
    span.set_attribute(A.GEN_AI_TOKENS_TOTAL, ti + to)
    if "cost_usd" in r:
        span.set_attribute(A.GEN_AI_COST_USD, float(r["cost_usd"]))
    else:
        span.set_attribute(A.FORGE_COST_UNKNOWN, True)
    if "tool_calls" in r:
        span.set_attribute(A.GEN_AI_TOOL_CALLS, int(r["tool_calls"]))
    if "finish_reasons" in r:
        span.set_attribute(A.GEN_AI_RESPONSE_FINISH_REASONS,
                           tuple(r["finish_reasons"]))
    if "agent_id" in r:
        span.set_attribute(A.GEN_AI_AGENT_ID, str(r["agent_id"]))


@contextlib.contextmanager
def tool_span(*, name: str, call_id: str | None = None) -> Iterator[Any]:
    if not _STATE.enabled:
        yield None
        return
    with _STATE.tracer.start_as_current_span(f"tool.{name}") as span:
        span.set_attribute(A.GEN_AI_OPERATION_NAME, A.OP_EXECUTE_TOOL)
        span.set_attribute(A.GEN_AI_TOOL_NAME, name)
        if call_id:
            span.set_attribute(A.GEN_AI_TOOL_CALL_ID, call_id)
        yield span


def record_agent_result(result: dict) -> None:
    """Attach result to the currently active agent span."""
    if not _STATE.enabled:
        return
    from opentelemetry import trace
    span = trace.get_current_span()
    if span is None:
        return
    sid = span.get_span_context().span_id
    # If we are inside an agent_span, buffer the result so _apply_agent_result
    # picks it up at span close; otherwise apply immediately.
    if sid in _TOTAL_RESULT:
        _TOTAL_RESULT[sid] = result
    else:
        _apply_agent_result(span, result)


def replay(*, events_path: str, config: dict) -> int:
    """Authoritative recovery: rebuild spans from the event log."""
    if not config.get("enabled", False):
        return 0
    from hooks._py.event_to_span import replay_events  # Task 10
    return replay_events(events_path=events_path, config=config)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/python/test_otel_emission.py -v`
Expected: PASS — 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/otel.py tests/python/test_otel_emission.py
git commit -m "feat(phase09): wire real span emission with semconv attributes"
```

---

### Task 6: Cardinality unit test (span names use only bounded values)

**Files:**
- Test: `tests/python/test_otel_cardinality.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/python/test_otel_cardinality.py
import pytest
pytest.importorskip("opentelemetry.sdk.trace")

from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter
from opentelemetry.sdk.trace.export import SimpleSpanProcessor

from hooks._py import otel
from hooks._py import otel_attributes as A


def _enable(monkeypatch):
    exporter = InMemorySpanExporter()
    monkeypatch.setattr(otel, "_build_processor",
                        lambda cfg: SimpleSpanProcessor(exporter), raising=False)
    otel.init({"enabled": True, "service_name": "forge-pipeline",
               "sample_rate": 1.0, "exporter": "console",
               "endpoint": "", "batch_size": 1, "flush_interval_seconds": 1})
    return exporter


def test_run_id_never_appears_in_span_names(monkeypatch):
    exporter = _enable(monkeypatch)
    run_id = "e8b3e1c4-ffee-4f0b-9a42-7d6dcf6cb1d0"
    with otel.pipeline_span(run_id=run_id, mode="standard"):
        with otel.stage_span("EXPLORING"):
            with otel.agent_span(name="fg-100-orchestrator",
                                  model="claude-sonnet-4-7",
                                  description="Coordinator"):
                pass
    otel.shutdown()
    for span in exporter.get_finished_spans():
        # Span NAME must never contain a high-cardinality attribute.
        assert run_id not in span.name, f"run_id leaked into span name: {span.name}"
        # run_id must still be present as an attribute on the pipeline span.
    pipeline = [s for s in exporter.get_finished_spans() if s.name == "pipeline"][0]
    assert pipeline.attributes[A.FORGE_RUN_ID] == run_id


def test_span_names_are_enumerable():
    # Expected span-name set is bounded + deterministic.
    # pipeline, stage.<STAGE>, agent.<agent_name>, tool.<tool_name>, batch.review-round-<N>
    allowed_prefixes = ("pipeline", "stage.", "agent.", "tool.", "batch.")
    import inspect
    src = inspect.getsource(otel)
    for prefix in allowed_prefixes:
        assert prefix in src, f"expected span-name prefix {prefix!r} in otel.py source"
```

- [ ] **Step 2: Run test to verify it fails then passes**

Run: `pytest tests/python/test_otel_cardinality.py -v`
Expected: PASS (Task 5 already implements bounded naming). If it fails, the implementation is leaking `run_id` into a name — fix the emitter, not the test.

- [ ] **Step 3: Commit**

```bash
git add tests/python/test_otel_cardinality.py
git commit -m "test(phase09): enforce span-name cardinality budget"
```

---

### Task 7: `events.jsonl` → span translator — unit fixture + schema

**Files:**
- Create: `tests/fixtures/events-sample.jsonl`
- Create: `hooks/_py/event_to_span.py` (skeleton)
- Test: `tests/python/test_event_to_span.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/python/test_event_to_span.py
import json
from pathlib import Path

import pytest
pytest.importorskip("opentelemetry.sdk.trace")

from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter
from opentelemetry.sdk.trace.export import SimpleSpanProcessor

from hooks._py import otel
from hooks._py.event_to_span import iter_span_ops, EventOp

FIXTURE = Path(__file__).parent.parent / "fixtures" / "events-sample.jsonl"


def test_fixture_parses_to_ordered_ops():
    ops = list(iter_span_ops(str(FIXTURE)))
    # Expected sequence: pipeline.open, stage.open, agent.open, agent.close,
    # stage.close, pipeline.close.
    kinds = [(o.kind, o.name) for o in ops]
    assert kinds == [
        ("open", "pipeline"),
        ("open", "stage.PLANNING"),
        ("open", "agent.fg-200-planner"),
        ("close", "agent.fg-200-planner"),
        ("close", "stage.PLANNING"),
        ("close", "pipeline"),
    ]


def test_op_carries_attributes():
    ops = list(iter_span_ops(str(FIXTURE)))
    agent_open = next(o for o in ops if o.kind == "open"
                      and o.name == "agent.fg-200-planner")
    assert agent_open.attrs["gen_ai.agent.name"] == "fg-200-planner"
    assert agent_open.attrs["gen_ai.request.model"] == "claude-sonnet-4-7"
    agent_close = next(o for o in ops if o.kind == "close"
                        and o.name == "agent.fg-200-planner")
    assert agent_close.attrs["gen_ai.tokens.input"] == 1200
    assert agent_close.attrs["gen_ai.tokens.output"] == 800
    assert agent_close.attrs["gen_ai.cost.usd"] == pytest.approx(0.018)
```

- [ ] **Step 2: Write the fixture**

Create `tests/fixtures/events-sample.jsonl` with exactly these 6 lines (one JSON object per line):

```jsonl
{"ts": "2026-04-19T10:00:00Z", "type": "pipeline.open", "run_id": "r-sample", "mode": "standard"}
{"ts": "2026-04-19T10:00:01Z", "type": "stage.open", "stage": "PLANNING"}
{"ts": "2026-04-19T10:00:02Z", "type": "agent.open", "agent_name": "fg-200-planner", "model": "claude-sonnet-4-7", "description": "Pipeline planner"}
{"ts": "2026-04-19T10:00:30Z", "type": "agent.close", "agent_name": "fg-200-planner", "tokens_input": 1200, "tokens_output": 800, "cost_usd": 0.018, "tool_calls": 5, "finish_reasons": ["stop"]}
{"ts": "2026-04-19T10:00:31Z", "type": "stage.close", "stage": "PLANNING"}
{"ts": "2026-04-19T10:00:32Z", "type": "pipeline.close", "run_id": "r-sample"}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `pytest tests/python/test_event_to_span.py -v`
Expected: FAIL — `ModuleNotFoundError: hooks._py.event_to_span`.

- [ ] **Step 4: Write the translator**

```python
# hooks/_py/event_to_span.py
"""Translate .forge/events.jsonl rows into OTel span open/close operations.

The event log (Phase F07) is fsync'd per row. This module is the
authoritative-replay translator — live emission (otel.py) and replay emit
the same spans byte-for-byte except for timestamps.
"""
from __future__ import annotations

import dataclasses
import json
from typing import Iterator

from hooks._py import otel_attributes as A


@dataclasses.dataclass(frozen=True)
class EventOp:
    kind: str                       # "open" | "close"
    name: str                       # span name (bounded)
    attrs: dict[str, object]        # semconv attributes


def _event_to_op(ev: dict) -> EventOp | None:
    t = ev.get("type")
    if t == "pipeline.open":
        return EventOp("open", "pipeline", {
            A.GEN_AI_AGENT_NAME: "forge-pipeline",
            A.GEN_AI_OPERATION_NAME: A.OP_INVOKE_AGENT,
            A.FORGE_RUN_ID: ev["run_id"],
            A.FORGE_MODE: ev.get("mode", "standard"),
        })
    if t == "pipeline.close":
        return EventOp("close", "pipeline", {A.FORGE_RUN_ID: ev["run_id"]})
    if t == "stage.open":
        return EventOp("open", f"stage.{ev['stage']}", {A.FORGE_STAGE: ev["stage"]})
    if t == "stage.close":
        return EventOp("close", f"stage.{ev['stage']}", {A.FORGE_STAGE: ev["stage"]})
    if t == "agent.open":
        return EventOp("open", f"agent.{ev['agent_name']}", {
            A.GEN_AI_AGENT_NAME: ev["agent_name"],
            A.GEN_AI_AGENT_DESCRIPTION: ev.get("description", ""),
            A.GEN_AI_OPERATION_NAME: A.OP_INVOKE_AGENT,
            A.GEN_AI_REQUEST_MODEL: ev.get("model", "unknown"),
        })
    if t == "agent.close":
        ti = int(ev.get("tokens_input", 0))
        to = int(ev.get("tokens_output", 0))
        attrs: dict[str, object] = {
            A.GEN_AI_AGENT_NAME: ev["agent_name"],
            A.GEN_AI_TOKENS_INPUT: ti,
            A.GEN_AI_TOKENS_OUTPUT: to,
            A.GEN_AI_TOKENS_TOTAL: ti + to,
        }
        if "cost_usd" in ev:
            attrs[A.GEN_AI_COST_USD] = float(ev["cost_usd"])
        else:
            attrs[A.FORGE_COST_UNKNOWN] = True
        if "tool_calls" in ev:
            attrs[A.GEN_AI_TOOL_CALLS] = int(ev["tool_calls"])
        if "finish_reasons" in ev:
            attrs[A.GEN_AI_RESPONSE_FINISH_REASONS] = tuple(ev["finish_reasons"])
        return EventOp("close", f"agent.{ev['agent_name']}", attrs)
    return None  # unknown event types are ignored


def iter_span_ops(events_path: str) -> Iterator[EventOp]:
    with open(events_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            ev = json.loads(line)
            op = _event_to_op(ev)
            if op is not None:
                yield op


def replay_events(*, events_path: str, config: dict) -> int:  # stub; wired in Task 10
    count = 0
    for _ in iter_span_ops(events_path):
        count += 1
    return count
```

- [ ] **Step 5: Run test to verify it passes**

Run: `pytest tests/python/test_event_to_span.py -v`
Expected: PASS — 2 tests pass.

- [ ] **Step 6: Commit**

```bash
git add hooks/_py/event_to_span.py tests/fixtures/events-sample.jsonl tests/python/test_event_to_span.py
git commit -m "feat(phase09): add events.jsonl -> OTel span translator"
```

---

### Task 8: Emit event-mirror from `state_write.py` (Phase 02 integration)

**Files:**
- Modify: `hooks/_py/state_write.py` (assumes Phase 02 shipped this module)
- Create: `hooks/_py/otel.py::emit_event_mirror` (small public helper)
- Test: `tests/python/test_event_mirror.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/python/test_event_mirror.py
import pytest
pytest.importorskip("opentelemetry.sdk.trace")

from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter
from opentelemetry.sdk.trace.export import SimpleSpanProcessor

from hooks._py import otel


def test_emit_event_mirror_applies_attrs_to_active_span(monkeypatch):
    exporter = InMemorySpanExporter()
    monkeypatch.setattr(otel, "_build_processor",
                        lambda cfg: SimpleSpanProcessor(exporter), raising=False)
    otel.init({"enabled": True, "sample_rate": 1.0, "exporter": "console",
               "endpoint": "", "batch_size": 1, "flush_interval_seconds": 1})
    with otel.pipeline_span(run_id="r1", mode="standard"):
        with otel.stage_span("EXPLORING"):
            otel.emit_event_mirror({"type": "stage.progress",
                                      "forge.score": 85,
                                      "forge.phase_iterations": 3})
    otel.shutdown()
    stage = next(s for s in exporter.get_finished_spans() if s.name == "stage.EXPLORING")
    assert stage.attributes["forge.score"] == 85
    assert stage.attributes["forge.phase_iterations"] == 3
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/python/test_event_mirror.py -v`
Expected: FAIL — `AttributeError: module 'hooks._py.otel' has no attribute 'emit_event_mirror'`.

- [ ] **Step 3: Add `emit_event_mirror` to `hooks/_py/otel.py`**

Append:

```python
def emit_event_mirror(event: dict) -> None:
    """Mirror a state-write event onto the active span as attributes.

    Called by hooks/_py/state_write.py (Phase 02) after every event append
    to keep spans in lockstep with the event log. Unknown keys pass through
    as span attributes; keys prefixed with 'type' are ignored.
    """
    if not _STATE.enabled:
        return
    from opentelemetry import trace
    span = trace.get_current_span()
    if span is None:
        return
    for k, v in event.items():
        if k == "type":
            continue
        try:
            span.set_attribute(k, v)
        except Exception:  # noqa: BLE001 — attribute errors are non-fatal
            log.debug("failed to set attribute %s=%r", k, v)
```

- [ ] **Step 4: Wire the call in `state_write.py`**

Modify `hooks/_py/state_write.py` (Phase 02 file) — after the event-append block, add:

```python
# At the end of the append_event() function, AFTER fsync:
try:
    from hooks._py import otel as _otel
    _otel.emit_event_mirror(event)
except Exception:  # noqa: BLE001
    # OTel mirror is optional and must never block state writes.
    pass
```

- [ ] **Step 5: Run test to verify it passes**

Run: `pytest tests/python/test_event_mirror.py -v`
Expected: PASS — 1 test passes.

- [ ] **Step 6: Commit**

```bash
git add hooks/_py/otel.py hooks/_py/state_write.py tests/python/test_event_mirror.py
git commit -m "feat(phase09): mirror state-write events onto active span"
```

---

### Task 9: `TRACEPARENT` injection around subagent dispatch

**Files:**
- Modify: `hooks/_py/otel.py` (add `dispatch_env` helper)
- Test: `tests/python/test_dispatch_env.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/python/test_dispatch_env.py
import pytest
pytest.importorskip("opentelemetry.sdk.trace")

from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter
from opentelemetry.sdk.trace.export import SimpleSpanProcessor

from hooks._py import otel


def test_dispatch_env_includes_traceparent(monkeypatch):
    exporter = InMemorySpanExporter()
    monkeypatch.setattr(otel, "_build_processor",
                        lambda cfg: SimpleSpanProcessor(exporter), raising=False)
    otel.init({"enabled": True, "sample_rate": 1.0, "exporter": "console",
               "endpoint": "", "batch_size": 1, "flush_interval_seconds": 1})
    env_before = {"FOO": "bar"}
    with otel.pipeline_span(run_id="r1", mode="standard"):
        env_after = otel.dispatch_env(env_before)
    otel.shutdown()
    # Original dict unmodified; returned env has TRACEPARENT.
    assert env_before == {"FOO": "bar"}
    assert "TRACEPARENT" in env_after
    assert env_after["FOO"] == "bar"
    # W3C format sanity check.
    assert env_after["TRACEPARENT"].count("-") == 3


def test_dispatch_env_disabled_returns_copy():
    otel.init({"enabled": False})
    assert otel.dispatch_env({"A": "1"}) == {"A": "1"}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/python/test_dispatch_env.py -v`
Expected: FAIL — `AttributeError: module 'hooks._py.otel' has no attribute 'dispatch_env'`.

- [ ] **Step 3: Implement**

Append to `hooks/_py/otel.py`:

```python
def dispatch_env(base_env: dict[str, str]) -> dict[str, str]:
    """Return a copy of `base_env` augmented with TRACEPARENT/TRACESTATE.

    The orchestrator calls this immediately before a Task-tool dispatch to
    give the subagent process the current span context.
    """
    env = dict(base_env)
    if not _STATE.enabled:
        return env
    from hooks._py.otel_context import inject_traceparent_env
    inject_traceparent_env(env)
    return env
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/python/test_dispatch_env.py -v`
Expected: PASS — 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/otel.py tests/python/test_dispatch_env.py
git commit -m "feat(phase09): add dispatch_env helper for TRACEPARENT propagation"
```

---

### Task 10: `replay()` full implementation + CLI

**Files:**
- Modify: `hooks/_py/event_to_span.py`
- Create: `hooks/_py/otel_cli.py`
- Test: `tests/python/test_otel_replay.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/python/test_otel_replay.py
import subprocess
import sys
from pathlib import Path

import pytest
pytest.importorskip("opentelemetry.sdk.trace")

from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter
from opentelemetry.sdk.trace.export import SimpleSpanProcessor

from hooks._py import otel, event_to_span

FIXTURE = Path(__file__).parent.parent / "fixtures" / "events-sample.jsonl"


def test_replay_emits_deterministic_spans(monkeypatch):
    exporter = InMemorySpanExporter()
    monkeypatch.setattr(otel, "_build_processor",
                        lambda cfg: SimpleSpanProcessor(exporter), raising=False)
    n = otel.replay(events_path=str(FIXTURE),
                     config={"enabled": True, "sample_rate": 1.0,
                             "exporter": "console", "endpoint": "",
                             "batch_size": 1, "flush_interval_seconds": 1,
                             "service_name": "forge-pipeline"})
    assert n == 3  # pipeline + stage + agent
    names = sorted(s.name for s in exporter.get_finished_spans())
    assert names == ["agent.fg-200-planner", "pipeline", "stage.PLANNING"]
    trace_ids = {s.context.trace_id for s in exporter.get_finished_spans()}
    assert len(trace_ids) == 1  # one trace, three spans


def test_replay_cli_runs(tmp_path):
    out = subprocess.run([sys.executable, "-m", "hooks._py.otel_cli",
                          "replay", "--from-events", str(FIXTURE),
                          "--exporter", "console", "--sample-rate", "1.0"],
                         capture_output=True, text=True, timeout=30,
                         env={"PATH": "/usr/bin:/bin"})
    assert out.returncode == 0, out.stderr
    assert "replayed" in out.stdout.lower()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/python/test_otel_replay.py -v`
Expected: FAIL — `replay_events` returns count only; CLI missing.

- [ ] **Step 3: Implement `replay_events`**

Replace `replay_events` in `hooks/_py/event_to_span.py`:

```python
def replay_events(*, events_path: str, config: dict) -> int:
    """Rebuild spans from an event log and emit via the configured exporter.

    This is the AUTHORITATIVE recovery path — idempotent and deterministic
    when given the same event log (modulo timestamps). The live stream is
    best-effort; this is the source of truth.
    """
    from hooks._py import otel as _otel
    _otel.init(config)
    if not _otel._STATE.enabled:
        return 0
    stack: list = []          # names of currently open spans
    cms: list = []            # active context managers (to close in reverse)
    count = 0
    try:
        for op in iter_span_ops(events_path):
            if op.kind == "open":
                name = op.name
                if name == "pipeline":
                    cm = _otel.pipeline_span(
                        run_id=op.attrs.get("forge.run_id", "unknown"),
                        mode=op.attrs.get("forge.mode", "standard"),
                    )
                elif name.startswith("stage."):
                    cm = _otel.stage_span(name.split(".", 1)[1])
                elif name.startswith("agent."):
                    cm = _otel.agent_span(
                        name=op.attrs.get("gen_ai.agent.name", name.split(".", 1)[1]),
                        model=op.attrs.get("gen_ai.request.model", "unknown"),
                        description=op.attrs.get("gen_ai.agent.description", ""),
                    )
                else:
                    continue
                cm.__enter__()
                cms.append(cm)
                stack.append(name)
                count += 1
            elif op.kind == "close":
                # Apply close-time attributes (tokens, cost, tool calls) before
                # exiting so they land on the same span.
                if op.name.startswith("agent."):
                    _otel.record_agent_result({
                        "tokens_input": op.attrs.get("gen_ai.tokens.input", 0),
                        "tokens_output": op.attrs.get("gen_ai.tokens.output", 0),
                        "cost_usd": op.attrs.get("gen_ai.cost.usd"),
                        "tool_calls": op.attrs.get("gen_ai.tool.calls"),
                        "finish_reasons": list(op.attrs.get("gen_ai.response.finish_reasons", ())),
                    })
                if stack and stack[-1] == op.name:
                    cms.pop().__exit__(None, None, None)
                    stack.pop()
    finally:
        # Close any still-open spans (malformed log).
        while cms:
            cms.pop().__exit__(None, None, None)
        _otel.shutdown()
    return count
```

- [ ] **Step 4: Create the CLI**

```python
# hooks/_py/otel_cli.py
"""forge OTel CLI.

Usage:
  python -m hooks._py.otel_cli replay --from-events <path> [options]
"""
from __future__ import annotations

import argparse
import sys

from hooks._py import otel


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="forge-otel")
    sub = parser.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("replay", help="Rebuild spans from an event log")
    r.add_argument("--from-events", required=True)
    r.add_argument("--exporter", default="grpc",
                   choices=["grpc", "http", "console"])
    r.add_argument("--endpoint", default="http://localhost:4317")
    r.add_argument("--sample-rate", type=float, default=1.0)
    r.add_argument("--service-name", default="forge-pipeline")

    args = parser.parse_args(argv)
    if args.cmd == "replay":
        n = otel.replay(events_path=args.from_events, config={
            "enabled": True,
            "exporter": args.exporter,
            "endpoint": args.endpoint,
            "sample_rate": args.sample_rate,
            "service_name": args.service_name,
            "batch_size": 32,
            "flush_interval_seconds": 2,
        })
        print(f"replayed {n} spans from {args.from_events}")
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 5: Run test to verify it passes**

Run: `pytest tests/python/test_otel_replay.py -v`
Expected: PASS — 2 tests pass.

- [ ] **Step 6: Commit**

```bash
git add hooks/_py/event_to_span.py hooks/_py/otel_cli.py tests/python/test_otel_replay.py
git commit -m "feat(phase09): implement authoritative replay + CLI entry point"
```

---

### Task 11: OpenInference opt-in compatibility attributes

**Files:**
- Modify: `hooks/_py/otel.py`
- Test: `tests/python/test_openinference_compat.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/python/test_openinference_compat.py
import pytest
pytest.importorskip("opentelemetry.sdk.trace")

from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter
from opentelemetry.sdk.trace.export import SimpleSpanProcessor

from hooks._py import otel


def _enable(monkeypatch, openinference: bool):
    exporter = InMemorySpanExporter()
    monkeypatch.setattr(otel, "_build_processor",
                        lambda cfg: SimpleSpanProcessor(exporter), raising=False)
    otel.init({"enabled": True, "sample_rate": 1.0, "exporter": "console",
               "endpoint": "", "batch_size": 1, "flush_interval_seconds": 1,
               "openinference_compat": openinference})
    return exporter


def test_openinference_off_emits_only_gen_ai(monkeypatch):
    exporter = _enable(monkeypatch, openinference=False)
    with otel.pipeline_span(run_id="r1", mode="standard"):
        with otel.agent_span(name="fg-100-orchestrator", model="sonnet",
                              description="Coordinator"):
            pass
    otel.shutdown()
    agent = next(s for s in exporter.get_finished_spans() if s.name.startswith("agent."))
    assert "openinference.span.kind" not in agent.attributes


def test_openinference_on_emits_duplicate_attrs(monkeypatch):
    exporter = _enable(monkeypatch, openinference=True)
    with otel.pipeline_span(run_id="r1", mode="standard"):
        with otel.agent_span(name="fg-100-orchestrator", model="sonnet",
                              description="Coordinator"):
            otel.record_agent_result({"tokens_input": 10, "tokens_output": 20,
                                         "cost_usd": 0.001, "tool_calls": 0})
    otel.shutdown()
    agent = next(s for s in exporter.get_finished_spans() if s.name.startswith("agent."))
    # OpenInference mirrors.
    assert agent.attributes["openinference.span.kind"] == "AGENT"
    assert agent.attributes["llm.token_count.prompt"] == 10
    assert agent.attributes["llm.token_count.completion"] == 20
    assert agent.attributes["llm.token_count.total"] == 30
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/python/test_openinference_compat.py -v`
Expected: FAIL — first test passes, second fails on `openinference.span.kind`.

- [ ] **Step 3: Extend `agent_span` + `_apply_agent_result`**

In `hooks/_py/otel.py`, inside `agent_span` after setting gen_ai attributes, add:

```python
        if _STATE.cfg.get("openinference_compat", False):
            span.set_attribute("openinference.span.kind", "AGENT")
            span.set_attribute("llm.model_name", model)
            span.set_attribute("agent.name", name)
```

And inside `_apply_agent_result`, after the gen_ai.tokens.* sets:

```python
    if _STATE.cfg.get("openinference_compat", False):
        span.set_attribute("llm.token_count.prompt", ti)
        span.set_attribute("llm.token_count.completion", to)
        span.set_attribute("llm.token_count.total", ti + to)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/python/test_openinference_compat.py -v`
Expected: PASS — 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/otel.py tests/python/test_openinference_compat.py
git commit -m "feat(phase09): add opt-in OpenInference compatibility attributes"
```

---

### Task 12: Pin semconv JSON Schema

**Files:**
- Create: `shared/schemas/otel-genai-v1.json`
- Create: `tests/python/otel_semconv_validator.py`
- Test: `tests/python/test_otel_schema.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/python/test_otel_schema.py
import json
from pathlib import Path

import pytest

SCHEMA = Path(__file__).parent.parent.parent / "shared" / "schemas" / "otel-genai-v1.json"


def test_schema_file_exists_and_is_valid_json():
    assert SCHEMA.exists(), "pinned semconv schema missing"
    data = json.loads(SCHEMA.read_text())
    assert data.get("$schema", "").startswith("https://json-schema.org/")
    assert "properties" in data
    required_attrs = data["properties"]["agent_span"]["required"]
    for a in ("gen_ai.agent.name", "gen_ai.operation.name", "gen_ai.request.model"):
        assert a in required_attrs


def test_validator_accepts_emitted_spans():
    from tests.python.otel_semconv_validator import validate_spans
    good = [{
        "name": "agent.fg-200-planner",
        "attributes": {
            "gen_ai.agent.name": "fg-200-planner",
            "gen_ai.operation.name": "invoke_agent",
            "gen_ai.request.model": "claude-sonnet-4-7",
            "gen_ai.tokens.input": 10,
            "gen_ai.tokens.output": 20,
            "gen_ai.tokens.total": 30,
        },
        "kind": "agent",
    }]
    errors = validate_spans(good)
    assert errors == []


def test_validator_rejects_missing_required_attribute():
    from tests.python.otel_semconv_validator import validate_spans
    bad = [{
        "name": "agent.x",
        "attributes": {"gen_ai.agent.name": "x", "gen_ai.operation.name": "invoke_agent"},
        "kind": "agent",
    }]
    errors = validate_spans(bad)
    assert any("gen_ai.request.model" in e for e in errors)


def test_validator_rejects_token_math_violation():
    from tests.python.otel_semconv_validator import validate_spans
    bad = [{
        "name": "agent.x",
        "attributes": {
            "gen_ai.agent.name": "x",
            "gen_ai.operation.name": "invoke_agent",
            "gen_ai.request.model": "m",
            "gen_ai.tokens.input": 10,
            "gen_ai.tokens.output": 20,
            "gen_ai.tokens.total": 99,  # wrong
        },
        "kind": "agent",
    }]
    errors = validate_spans(bad)
    assert any("tokens.total" in e for e in errors)
```

- [ ] **Step 2: Write the schema**

Create `shared/schemas/otel-genai-v1.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://quantumbit.cz/forge/schemas/otel-genai-v1.json",
  "title": "OTel GenAI Semantic Conventions — forge pinned subset (2026-04)",
  "type": "object",
  "properties": {
    "agent_span": {
      "type": "object",
      "required": [
        "gen_ai.agent.name",
        "gen_ai.operation.name",
        "gen_ai.request.model"
      ],
      "properties": {
        "gen_ai.agent.name":       {"type": "string"},
        "gen_ai.agent.description":{"type": "string"},
        "gen_ai.agent.id":         {"type": "string"},
        "gen_ai.operation.name":   {"type": "string", "enum": ["invoke_agent", "execute_tool", "create_agent"]},
        "gen_ai.request.model":    {"type": "string"},
        "gen_ai.tokens.input":     {"type": "integer", "minimum": 0},
        "gen_ai.tokens.output":    {"type": "integer", "minimum": 0},
        "gen_ai.tokens.total":     {"type": "integer", "minimum": 0},
        "gen_ai.cost.usd":         {"type": "number",  "minimum": 0},
        "gen_ai.tool.calls":       {"type": "integer", "minimum": 0},
        "gen_ai.response.finish_reasons": {
          "type": "array",
          "items": {"type": "string"}
        }
      }
    },
    "tool_span": {
      "type": "object",
      "required": ["gen_ai.operation.name", "gen_ai.tool.name"],
      "properties": {
        "gen_ai.operation.name": {"const": "execute_tool"},
        "gen_ai.tool.name":      {"type": "string"},
        "gen_ai.tool.call.id":   {"type": "string"}
      }
    }
  }
}
```

- [ ] **Step 3: Write the validator**

```python
# tests/python/otel_semconv_validator.py
"""CI validator: semconv schema + tokens.total consistency + hierarchy."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Iterable

import jsonschema

_SCHEMA = json.loads(
    (Path(__file__).parent.parent.parent / "shared" / "schemas" / "otel-genai-v1.json").read_text()
)


def validate_spans(spans: Iterable[dict]) -> list[str]:
    errors: list[str] = []
    for span in spans:
        kind = span.get("kind", "")
        attrs = span.get("attributes", {})
        if kind == "agent":
            schema = _SCHEMA["properties"]["agent_span"]
        elif kind == "tool":
            schema = _SCHEMA["properties"]["tool_span"]
        else:
            continue
        try:
            jsonschema.validate(instance=attrs, schema=schema)
        except jsonschema.ValidationError as e:
            errors.append(f"{span.get('name', '?')}: {e.message}")
        # tokens.total consistency
        if kind == "agent":
            ti = attrs.get("gen_ai.tokens.input")
            to = attrs.get("gen_ai.tokens.output")
            tt = attrs.get("gen_ai.tokens.total")
            if ti is not None and to is not None and tt is not None and ti + to != tt:
                errors.append(
                    f"{span.get('name', '?')}: gen_ai.tokens.total={tt} != input+output={ti+to}"
                )
    return errors


def validate_hierarchy(spans: list[dict]) -> list[str]:
    """Every non-root span must share the pipeline root's trace_id."""
    errors = []
    roots = [s for s in spans if s.get("name") == "pipeline"]
    if not roots:
        return ["no pipeline root span"]
    root_tid = roots[0].get("trace_id")
    for s in spans:
        if s.get("trace_id") != root_tid:
            errors.append(f"{s.get('name', '?')}: trace_id mismatch (orphan)")
    return errors
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/python/test_otel_schema.py -v`
Expected: PASS — 4 tests pass (install `jsonschema` if missing).

- [ ] **Step 5: Commit**

```bash
git add shared/schemas/otel-genai-v1.json tests/python/otel_semconv_validator.py tests/python/test_otel_schema.py
git commit -m "feat(phase09): pin OTel GenAI semconv schema + semconv validator"
```

---

### Task 13: CI — Docker collector sidecar + semconv validation job

**Files:**
- Create: `.github/workflows/phase09-otel.yml`

- [ ] **Step 1: Write the workflow**

```yaml
# .github/workflows/phase09-otel.yml
name: phase09-otel

on:
  pull_request:
    paths:
      - 'hooks/_py/otel*.py'
      - 'hooks/_py/event_to_span.py'
      - 'shared/schemas/otel-genai-v1.json'
      - 'tests/python/**'
      - '.github/workflows/phase09-otel.yml'

jobs:
  otel-semconv-validation:
    runs-on: ubuntu-latest        # pinned: DinD flakes on macOS runners.
    services:
      otel-collector:
        image: otel/opentelemetry-collector-contrib:0.105.0
        ports:
          - 4317:4317
          - 4318:4318
        volumes:
          - ${{ github.workspace }}/.github/otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml:ro
        options: >-
          --health-cmd "wget -qO- http://localhost:13133/ || exit 1"
          --health-interval 5s
          --health-timeout 3s
          --health-retries 10
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-python@v5
        with:
          python-version: "3.10"
      - name: Install deps
        run: |
          pip install opentelemetry-api==1.30.0 \
                      opentelemetry-sdk==1.30.0 \
                      opentelemetry-exporter-otlp==1.30.0 \
                      jsonschema pytest
      - name: Run Phase 01 eval with OTel enabled
        env:
          FORGE_OTEL_ENABLED: "true"
          FORGE_OTEL_EXPORTER: "grpc"
          FORGE_OTEL_ENDPOINT: "http://localhost:4317"
        run: |
          # Drive a canonical eval scenario that exercises every span kind.
          python -m tests.eval.run_phase01_scenario \
            --otel-enabled --collector-url http://localhost:4317
      - name: Validate emitted spans against pinned schema
        run: |
          python -m pytest tests/python/test_otel_schema.py -v
          python tests/python/otel_semconv_validator.py --spans /tmp/otel-out.jsonl

  otel-replay:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-python@v5
        with:
          python-version: "3.10"
      - name: Install deps
        run: |
          pip install opentelemetry-api==1.30.0 \
                      opentelemetry-sdk==1.30.0 \
                      opentelemetry-exporter-otlp==1.30.0 \
                      jsonschema pytest
      - name: Replay parity test
        run: pytest tests/python/test_otel_replay.py -v

  otel-disabled-overhead:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-python@v5
        with:
          python-version: "3.10"
      - name: Install deps
        run: pip install pytest
      - name: Verify no OTel imports and <1ms overhead when disabled
        run: |
          python -c "
          import time, hooks._py.otel as o
          o.init({'enabled': False})
          t0 = time.perf_counter_ns()
          for _ in range(1000):
              with o.stage_span('EXPLORING'):
                  pass
          elapsed_ms = (time.perf_counter_ns() - t0) / 1e6 / 1000
          assert elapsed_ms < 1.0, f'overhead {elapsed_ms}ms/stage exceeds 1ms budget'
          import sys
          for mod in list(sys.modules):
              assert not mod.startswith('opentelemetry'), f'imported {mod} when disabled'
          print(f'OK: {elapsed_ms:.4f}ms/stage, no OTel imports')
          "
```

- [ ] **Step 2: Create the collector config referenced by the workflow**

```yaml
# .github/otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

exporters:
  file:
    path: /tmp/otel-out.jsonl
    rotation:
      max_megabytes: 100

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [file]
  extensions: [health_check]

extensions:
  health_check:
    endpoint: 0.0.0.0:13133
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/phase09-otel.yml .github/otel-collector-config.yaml
git commit -m "ci(phase09): add OTel semconv validation, replay, and disabled-overhead jobs"
```

---

### Task 14: Rewrite `shared/observability.md`

**Files:**
- Modify: `shared/observability.md` (full rewrite)

- [ ] **Step 1: Write the new doc**

Replace `shared/observability.md` in full. The new doc must contain these sections in order:

```markdown
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

### Pipeline / stage / batch spans

- Carry `forge.*` attributes: `forge.run_id`, `forge.stage`, `forge.mode`,
  `forge.score`, `forge.phase_iterations`, `forge.convergence.iterations`,
  `forge.batch.size`, `forge.batch.agents`.

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

The bash exporter is deleted in Phase 09. No wrapper, no compatibility
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
```

- [ ] **Step 2: Commit**

```bash
git add shared/observability.md
git commit -m "docs(phase09): rewrite observability.md for OTel GenAI semconv"
```

---

### Task 15: Update `agents/fg-100-orchestrator.md` with OTel wrappers

**Files:**
- Modify: `agents/fg-100-orchestrator.md`

- [ ] **Step 1: Add the instrumentation contract**

Insert a new section after the existing "Pipeline flow" section:

```markdown
## OTel instrumentation (Phase 09)

Wrap every stage transition and subagent dispatch. Respects
`observability.otel.enabled` — when off, these calls are no-ops.

1. PREFLIGHT init:

       from hooks._py import otel
       otel.init(config.observability.otel,
                   parent_traceparent=os.environ.get("TRACEPARENT"))
       with otel.pipeline_span(run_id=state.run_id, mode=state.mode):
           # pipeline body

2. Stage transition:

       with otel.stage_span(state.stage):
           # stage body

3. Agent dispatch — MUST use `otel.dispatch_env(os.environ)` to
   propagate `TRACEPARENT` into the subagent:

       child_env = otel.dispatch_env(os.environ)
       with otel.agent_span(name=agent.name, model=agent.model,
                              description=agent.description):
           result = Agent(..., env=child_env)
           otel.record_agent_result({
               "tokens_input": result.tokens.input,
               "tokens_output": result.tokens.output,
               "cost_usd": result.cost_usd,
               "tool_calls": result.tool_calls,
               "finish_reasons": result.finish_reasons,
               "agent_id": result.agent_id,
           })

4. LEARNING shutdown:

       otel.shutdown()          # flushes pending batches
```

- [ ] **Step 2: Commit**

```bash
git add agents/fg-100-orchestrator.md
git commit -m "docs(phase09): document OTel instrumentation contract in orchestrator"
```

---

### Task 16: PREFLIGHT constraints + `plugin.json` extras

**Files:**
- Modify: `shared/preflight-constraints.md`
- Modify: `plugin.json`

- [ ] **Step 1: Append to `shared/preflight-constraints.md`**

```markdown
## `observability.otel.*`

| Parameter                                       | Type / Range          | Default           |
|-------------------------------------------------|-----------------------|-------------------|
| `observability.otel.enabled`                    | bool                  | `false`           |
| `observability.otel.endpoint`                   | non-empty when enabled| `""`              |
| `observability.otel.exporter`                   | grpc\|http\|console   | `grpc`            |
| `observability.otel.service_name`               | non-empty string      | `forge-pipeline`  |
| `observability.otel.sample_rate`                | 0.0–1.0               | `1.0`             |
| `observability.otel.openinference_compat`       | bool                  | `false`           |
| `observability.otel.include_tool_spans`         | bool                  | `false`           |
| `observability.otel.batch_size`                 | 1–1024                | `32`              |
| `observability.otel.flush_interval_seconds`     | 1–60                  | `2`               |

Violations log WARNING and fall back to defaults. When `enabled=true` but
`opentelemetry-api` is not importable, WARNING + disable for the run.
```

- [ ] **Step 2: Modify `plugin.json`**

Add an `optional_dependencies` block (append to the existing JSON):

```json
  "optional_dependencies": {
    "otel": [
      "opentelemetry-api>=1.30.0",
      "opentelemetry-sdk>=1.30.0",
      "opentelemetry-exporter-otlp>=1.30.0",
      "jsonschema>=4.0.0"
    ]
  }
```

- [ ] **Step 3: Commit**

```bash
git add shared/preflight-constraints.md plugin.json
git commit -m "chore(phase09): declare observability.otel.* constraints + [otel] extra"
```

---

### Task 17: `CHANGELOG.md` breaking-change notice

**Files:**
- Modify: `CHANGELOG.md` (create if absent)

- [ ] **Step 1: Prepend a new release entry**

```markdown
## [3.1.0] — 2026-05

### Breaking

- **OTel exporter rewritten in Python.** `shared/forge-otel-export.sh` is
  **removed**. Use `python -m hooks._py.otel_cli replay ...` for post-hoc
  export from the event log. Live emission happens automatically via
  `hooks/_py/otel.py` when `observability.otel.enabled=true`.
- **Attribute rename** — legacy custom names removed; semconv replacements:
  `tokens_in` → `gen_ai.tokens.input`, `tokens_out` → `gen_ai.tokens.output`,
  `agent` → `gen_ai.agent.name`, `model` → `gen_ai.request.model`,
  `findings_count` → `forge.findings.count`. Rebuild dashboards keyed on
  the old names.
- **Config keys removed.** Replace `observability.export` and
  `observability.otel_endpoint` with the nested `observability.otel.*` form
  documented in `shared/observability.md`. `telemetry.export_status` is no
  longer written to `state.json`.

### Added

- OTel GenAI Semantic Conventions (2026) span emission per pipeline, stage,
  and agent dispatch.
- W3C Trace Context propagation to subagent dispatches via `TRACEPARENT`.
- `ParentBased(TraceIdRatioBased)` sampler — subagent decisions inherit the
  root.
- `otel.replay()` — authoritative recovery from `.forge/events.jsonl`.
- Optional OpenInference compatibility mirror
  (`observability.otel.openinference_compat`).
- CI schema validator + semconv conformance test (`phase09-otel.yml`).
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(phase09): changelog entry for OTel GenAI semconv migration"
```

---

### Task 18: Delete `shared/forge-otel-export.sh` + version bump

**Files:**
- Delete: `shared/forge-otel-export.sh`
- Modify: `plugin.json` (version `3.0.0` → `3.1.0`)
- Modify: `CLAUDE.md` (update version marker at line 5)

- [ ] **Step 1: Remove the legacy script**

```bash
git rm shared/forge-otel-export.sh
```

- [ ] **Step 2: Grep for any residual references and remove them**

Run: `grep -rn "forge-otel-export" . --include="*.md" --include="*.sh" --include="*.py" --include="*.json"`
Expected: only this plan, CHANGELOG.md, and commit messages reference the name. Any documentation still pointing at it is stale — remove the line in each hit.

If the grep above finds hits outside `docs/superpowers/` and `CHANGELOG.md`, edit each file to drop the reference. Common suspects: `shared/observability.md` (handled in Task 14), `tests/validate-plugin.sh`, and `CLAUDE.md` (the `forge-otel-export.sh` row in the "shared scripts" table).

- [ ] **Step 3: Bump version**

In `plugin.json`:

```diff
-  "version": "3.0.0",
+  "version": "3.1.0",
```

In `CLAUDE.md` line 5:

```diff
-`forge` is a Claude Code plugin (v3.0.0, ...
+`forge` is a Claude Code plugin (v3.1.0, ...
```

In the `shared/` scripts table in `CLAUDE.md`, remove the `forge-otel-export.sh` row (there isn't one currently — verify with grep).

- [ ] **Step 4: Run full test suite locally (structural only, per CLAUDE.md "no local tests" rule)**

Run: `./tests/validate-plugin.sh`
Expected: PASS — 73+ structural checks, ~2s. If any check fails (missing frontmatter, broken cross-reference), fix inline before committing.

- [ ] **Step 5: Commit**

```bash
git add plugin.json CLAUDE.md
git rm shared/forge-otel-export.sh
# plus any files edited in Step 2 to drop stale references
git commit -m "feat(phase09)!: delete legacy bash OTel exporter, bump to 3.1.0

BREAKING CHANGE: shared/forge-otel-export.sh is removed. Use the Python
emitter (hooks/_py/otel.py) for live telemetry and
'python -m hooks._py.otel_cli replay' for post-hoc recovery from the event
log. See CHANGELOG.md for the full attribute + config rename mapping."
```

---

## Self-Review

**1. Spec coverage** — every §3 in-scope item maps to a task:

| Spec item | Task |
|---|---|
| §3.1 new Python emitter | 1, 2, 3, 5 |
| §3.2 spans (pipeline/stage/agent/tool) | 5 |
| §3.3 semconv attributes | 1, 5 |
| §3.4 exporters (grpc/http/console) | 3 |
| §3.5 W3C trace-context propagation | 4, 9 |
| §3.6 event-sourced emission | 7, 8 |
| §3.7 live streaming (best-effort + replay authoritative) | 5, 10 (doc'd 14) |
| §3.8 configuration | 16 |
| §3.9 CI schema validator | 12, 13 |
| §4.6 OpenInference opt-in | 11 |
| §5 Deleted: forge-otel-export.sh | 18 |
| §6 PREFLIGHT constraints | 16 |
| §9 rollout (version bump, no dual-path) | 17, 18 |

**2. Placeholder scan** — grep for TBD/TODO/fill-in/etc. in this plan: none present. Every step shows code or the exact edit.

**3. Type/name consistency** — verified:
- `otel.init`, `otel.shutdown`, `otel.pipeline_span`, `otel.stage_span`, `otel.agent_span`, `otel.tool_span`, `otel.record_agent_result`, `otel.replay`, `otel.dispatch_env`, `otel.emit_event_mirror` — consistent across Tasks 2, 5, 8, 9, 10, 11, 15.
- `build_sampler(sample_rate=...)` — Task 3 definition matches Task 5 caller.
- `build_exporter(kind=..., endpoint=..., headers=None)` — Task 3 definition matches Task 5 `_build_processor`.
- `inject_traceparent_env(env)` / `extract_parent_from_env()` / `TRACEPARENT_ENV` — Task 4 definitions match Task 9 usage.
- `EventOp(kind, name, attrs)` / `iter_span_ops(events_path)` / `replay_events(events_path, config)` — Task 7 definitions match Task 10 usage.
- Attribute constants from Task 1 referenced identically in Tasks 5, 7, 8, 11.

**Review-issue fixes verified:**
1. §3.7 contradiction — resolved: Task 2 docstring + Task 14 "Durability contract" section explicitly make `replay()` authoritative; live stream documented as best-effort.
2. Sampler type — resolved: Task 3 implements `ParentBased(root=TraceIdRatioBased(sample_rate))` exclusively; Task 4 respects inbound `sampled=0`; Task 14 documents the invariant.
3. Cardinality budget — resolved: Task 1 `BOUNDED_ATTRS`/`UNBOUNDED_ATTRS`; Task 6 enforces span-name safety via assertion; Task 14 documents the budget table.

Plan ready for execution.
