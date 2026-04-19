# Phase 09 Spec Review — OpenTelemetry GenAI Semconv Emission

**Spec:** `docs/superpowers/specs/2026-04-19-09-otel-genai-semconv-design.md`
**Reviewer:** Senior Code Reviewer
**Date:** 2026-04-19
**Verdict:** APPROVE WITH MINOR FIXES

---

## Criteria Checklist

| # | Criterion | Status | Notes |
|---|-----------|--------|-------|
| 1 | All 12 sections present | PASS | Goal, Motivation, Scope, Architecture, Components, Data/State/Config, Compatibility, Testing, Rollout, Risks, Success Criteria, References — all present and non-trivial. |
| 2 | No placeholders | PASS | No `TBD`, `TODO`, `<fill-in>`, or `???` markers. Every field populated. Open questions are explicit with proposed defaults, which is correct per plan policy. |
| 3 | Every emitted attribute listed with semconv name | PASS | §3.3 + §4.4 enumerate every emitted attribute: `gen_ai.agent.name`, `gen_ai.agent.description`, `gen_ai.agent.id`, `gen_ai.operation.name`, `gen_ai.request.model`, `gen_ai.tokens.input/output/total`, `gen_ai.cost.usd`, `gen_ai.tool.calls`, `gen_ai.response.finish_reasons`, plus `forge.*` for forge-specific. |
| 4 | Trace context propagation mechanism specified (env var format) | PASS | §4.5 specifies W3C Trace Context, `TRACEPARENT` env var, exact format `{version}-{trace_id}-{span_id}-{flags}`, and `TRACESTATE` for baggage. Mechanism: `TraceContextTextMapPropagator().extract()`. |
| 5 | Exporter types enumerated | PASS | §3.4 + config key `exporter: grpc \| http \| console` in §6. OTLP/gRPC default, OTLP/HTTP (JSON + protobuf), console for debug. |
| 6 | Dependency on Phase 02 explicit | PASS | Stated in frontmatter (`Depends on: Phase 02`), §3.1, §4.3 (`state_write.py (from Phase 02)`), §9.1 ("Merge Phase 02 first"), and Success Criterion §11.6. |
| 7 | Synthetic CI backend test specified (collector Docker) | PASS | §8 CI additions: `otel/opentelemetry-collector-contrib:0.105.0` Docker sidecar with file exporter; validator script asserts semconv + hierarchy + trace-id propagation. Gated to `ubuntu-latest`. |
| 8 | Sampling strategy defined | PASS | `sample_rate: 1.0` config key with 0.0–1.0 range, default 100% (justified: "forge runs are rare"). PREFLIGHT constraint row 5 validates the range. |
| 9 | 2 alternatives rejected with rationale | PASS | §4.6: (A) Custom forge schema — rejected, permanent vendor-translation tax. (B) OpenInference — rejected as primary, Arize-centric pre-dates OTel GenAI; kept as opt-in via `openinference_compat` flag. |
| 10 | Migration from bash script explicit in Rollout | PASS | §9.2 lists deletion of `shared/forge-otel-export.sh` in the same PR; §4.3.6 covers `otel.replay()` as replacement for the one path the bash script covered; §5 Deleted + §7 breaking notice + CHANGELOG entry. |

All 10 criteria PASS. No critical blockers.

---

## Top 3 Issues

### 1. IMPORTANT — Batch loss window contradicts "live streaming" claim

§3.7 promises "a crashed run still produces partial telemetry" via 2s batch flush, but §10 admits "up to 2s of spans can be lost." The `BatchSpanProcessor` default behavior on SIGKILL is to drop in-memory batches entirely — a hard crash loses the *current* batch regardless of interval. The `otel.replay()` fallback mitigates this, but the spec should explicitly state that the live stream is best-effort and replay is authoritative. Recommend: clarify §3.7 wording from "crashed run still produces partial telemetry" → "crashed run's *flushed* batches survive; unflushed batches are recovered via `otel.replay()` post-hoc." Tightens the contract; prevents user misunderstanding of durability semantics.

### 2. IMPORTANT — `sample_rate` interacts with parent-based sampling ambiguously

§6 defines `sample_rate: 1.0` but does not specify the sampler type. For distributed traces with `TRACEPARENT` propagation (§4.5), the OTel default `ParentBased(TraceIdRatioBased(rate))` is required — otherwise child subagents will make independent sampling decisions and produce orphan partial traces that fail success criterion §11.3 ("every subagent span shares the pipeline's `trace_id`"). Recommend: add to §4.3 and §6 that the sampler is `ParentBased(root=TraceIdRatioBased(sample_rate))`, and note that child spans always follow the root decision. Also document behavior when an external `TRACEPARENT` arrives with `sampled=0` (forge should respect it).

### 3. SUGGESTION — Attribute cardinality risk in `agent.<agent_name>` span names

§4.4 names agent spans `agent.<agent_name>` (e.g., `agent.fg-300-implementer`). With 42 agents plus review batches and possibly tool spans, span-name cardinality stays bounded — fine. But `forge.run_id` in §4.4 (pipeline row) is high-cardinality per-run and lands on every span via propagation if accidentally promoted to a span name. Recommend: explicitly state in §4.4 that `forge.run_id` is attribute-only, never a span-name component; add a "cardinality budget" note listing bounded attributes (`gen_ai.agent.name`, `gen_ai.request.model`, `forge.stage`, `forge.mode`) vs unbounded (`forge.run_id`, `gen_ai.tool.call.id`, `gen_ai.agent.id`). Backends like Tempo meter cardinality; clarity here prevents future cost surprises.

---

## Strengths Worth Calling Out

- Event-sourced emission (§3.6, §4.3.6) decouples observability from state machine and gives clean replay semantics — well-considered.
- Optional dep with hard-fail-open (`forge[otel]`, WARNING + disable) is the right posture for a P1 feature.
- Open questions (§10) include proposed defaults, not just raised flags — actionable.
- Testing strategy respects project policy (no local tests, CI-only) and includes three distinct jobs (validation, replay parity, disabled-overhead smoke).
- Deletion of legacy bash exporter in the same PR (§5 Deleted, §9.2) matches the "no backcompat" stance in `CLAUDE.md`.

---

## Relevant Files

- Spec: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-09-otel-genai-semconv-design.md`
- Legacy exporter (to delete): `/Users/denissajnar/IdeaProjects/forge/shared/forge-otel-export.sh`
- Phase 02 dependency: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-02-cross-platform-python-hooks-design.md`
- Observability doc (to rewrite): `/Users/denissajnar/IdeaProjects/forge/shared/observability.md`
- Orchestrator (to update): `/Users/denissajnar/IdeaProjects/forge/agents/fg-100-orchestrator.md`
