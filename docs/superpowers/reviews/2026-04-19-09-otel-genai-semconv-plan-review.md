# Phase 09 Plan Review — OpenTelemetry GenAI Semconv Emission

**Plan:** `docs/superpowers/plans/2026-04-19-09-otel-genai-semconv-plan.md`
**Spec:** `docs/superpowers/specs/2026-04-19-09-otel-genai-semconv-design.md`
**Spec review:** `docs/superpowers/reviews/2026-04-19-09-otel-genai-semconv-spec-review.md`
**Reviewer:** Senior Code Reviewer
**Date:** 2026-04-19
**Verdict:** APPROVE WITH MINOR FIXES

---

## Criteria Checklist

| # | Criterion | Status | Notes |
|---|-----------|--------|-------|
| 1 | writing-plans format | PASS | Header with Goal/Architecture/Tech Stack/Dependency, file-structure table (new/modified/deleted), task decomposition with TDD 5-step pattern (fail/implement/pass/commit), self-review section. Checkbox `- [ ]` syntax used throughout. Opens with REQUIRED SUB-SKILL call-out per convention. |
| 2 | No placeholders | PASS | Scanned for TBD/TODO/FIXME/XXX/<fill-in>/???: none present. Every code block, shell command, and edit is concrete. Self-review explicitly claims this and it holds. |
| 3 | Type consistency (semconv names) | PASS | Attribute constant names in Task 1 (`GEN_AI_AGENT_NAME="gen_ai.agent.name"` etc.) are referenced identically in Tasks 5, 7, 8, 11; the fixture (Task 7) uses the literal semconv strings matching the constants; schema file (Task 12) uses the same keys; orchestrator doc (Task 15) uses the same public API shape. Function signatures (`build_sampler`, `build_exporter`, `inject_traceparent_env`, `iter_span_ops`, `replay_events`, `EventOp`) line up across tasks. |
| 4 | Each task commits | PASS | All 18 tasks end with a concrete `git commit -m "<conventional-commit>"` step. Commit types align with content (feat/test/docs/ci/chore). Task 18 uses a breaking-change commit with `!` marker and a HEREDOC-style message body. |
| 5 | Spec coverage | PASS | Self-review §1 maps every spec §3 in-scope item to a task. Cross-checked: emitter (Task 2+5), pipeline/stage/agent/tool spans (Task 5), all semconv attributes (Task 1+5), three exporters grpc/http/console (Task 3), W3C env var propagation (Task 4+9), event-sourced emission (Task 7+8), config keys (Task 16), CI collector (Task 13). |
| 6 | Review feedback addressed | PASS | The plan contains a dedicated "Review Issue Resolutions" table up front, plus repeat verification in the Self-Review at the end. (1) Replay authoritative — Task 2 public docstring + Task 14 "Durability contract" section + Task 10 `replay_events` docstring. (2) `ParentBased(TraceIdRatioBased)` — Task 3 `build_sampler` returns exactly this, tests assert it; Task 4 `test_extract_respects_sampled_zero` verifies inbound `sampled=0` propagation. (3) Cardinality budget — Task 1 `BOUNDED_ATTRS`/`UNBOUNDED_ATTRS` tuples with explicit classification, Task 6 asserts `run_id` never appears in span names, Task 14 documents the budget table. |
| 7 | Phase 02 dependency gate explicit | PASS | Frontmatter line 11: "Phase 02 MUST be merged first ... Merge-gated. Do not merge this PR before Phase 02." Task 8 modifies `hooks/_py/state_write.py` explicitly "(assumes Phase 02 shipped this module)". Imports everywhere use `hooks._py.*`. |
| 8 | Delete `shared/forge-otel-export.sh` task | PASS | Task 18 does `git rm shared/forge-otel-export.sh`, includes a grep-for-residual-references step with guidance on common suspects (`tests/validate-plugin.sh`, `CLAUDE.md`), and uses a breaking-change commit. Version bumped `3.0.0 → 3.1.0` in `plugin.json` AND `CLAUDE.md` line 5 in the same task. |
| 9 | OpenInference opt-in flag task | PASS | Task 11 dedicated to `openinference_compat` config flag with two tests (off emits gen_ai only, on mirrors `openinference.span.kind=AGENT`, `llm.token_count.*`, `llm.model_name`, `agent.name`). Default off (matches spec §4.6). Config key documented in Tasks 14 and 16. |
| 10 | Docker collector CI sidecar test | PASS | Task 13 creates `.github/workflows/phase09-otel.yml` with `otel/opentelemetry-collector-contrib:0.105.0` as a `services:` sidecar, pins `ubuntu-latest` (per spec risk mitigation re: macOS DinD), writes collector config to `/tmp/otel-out.jsonl` via file exporter, then runs `otel_semconv_validator.py --spans /tmp/otel-out.jsonl`. Three jobs total: validation, replay, disabled-overhead. |

All 10 criteria PASS. No critical blockers.

---

## Top 3 Issues

### 1. IMPORTANT — CI uses `python -m tests.eval.run_phase01_scenario`, which this plan never creates

Task 13's `otel-semconv-validation` job invokes `python -m tests.eval.run_phase01_scenario --otel-enabled --collector-url http://localhost:4317` (line 1890-1892), but no task in this plan creates that module. It is implicitly assumed to exist from Phase 01. If Phase 01 hasn't shipped it (or shipped it under a different name/path/flags), this CI job will `ModuleNotFoundError` on first run — making the central validation gate a no-op and undermining success criterion §11.1 ("zero schema violations"). Recommend: either (a) add a task that creates a minimal eval driver that exercises every span kind (pipeline/stage/agent/tool/batch), or (b) add a hard prerequisite note at the top of Task 13 asserting `tests/eval/run_phase01_scenario.py` exists with the exact `--otel-enabled --collector-url` CLI surface, and add a pre-check step in the CI job that fails fast with a clear message when the module is missing. The collector-reads-to-file step will silently pass with an empty `/tmp/otel-out.jsonl` today.

### 2. IMPORTANT — Task 13's `services:` + volume-mount pattern won't work on GitHub Actions

The workflow declares `otel-collector` under `services:` with `volumes: - ${{ github.workspace }}/.github/otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml:ro`. GitHub Actions `services:` containers are created **before** `actions/checkout@v6` runs, so `${{ github.workspace }}/.github/otel-collector-config.yaml` does not yet exist on the runner when the collector container starts. The collector will boot with its default config (no OTLP receiver, no file exporter, no `:4317` binding), and the validation job will hang or emit zero spans. Recommend: drop the `services:` sidecar pattern for this case and instead start the collector as an explicit `docker run -v $PWD/.github/otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml ...` step after checkout, or bake the collector config into a small Dockerfile in `.github/` that the workflow builds and runs. This is a common GitHub Actions gotcha that would cost a debug cycle in CI.

### 3. SUGGESTION — Task 6's source-inspection test is tautological; replace with a black-box assertion

`tests/python/test_otel_cardinality.py::test_span_names_are_enumerable` uses `inspect.getsource(otel)` and asserts that the string `"pipeline"`, `"stage."`, `"agent."`, `"tool."`, `"batch."` each appear in the module source. This passes trivially today (the strings are in the `start_as_current_span(...)` calls) and will keep passing even if a future refactor starts interpolating unbounded values into names, because the bounded prefix would still be a substring. A regression where `agent.{run_id}` is mistakenly emitted would NOT fail this test. Recommend: replace the source-grep with a behavioural assertion — emit representative spans for each kind, extract `span.name` from the exporter, and assert every emitted name matches the regex `^(pipeline|stage\.[A-Z_]+|agent\.[a-z0-9-]+|tool\.[a-z0-9_-]+|batch\.review-round-\d+)$`. That catches real cardinality regressions; the current test does not.

---

## Strengths Worth Calling Out

- **Explicit review-issue table at the top.** Tying each spec-review finding to a specific task up front makes the traceability obvious and the Self-Review at the bottom re-verifies each one.
- **TDD 5-step pattern applied uniformly** — every task writes a failing test first, shows expected failure, implements, asserts pass, commits. Makes each task independently verifiable.
- **Authoritative replay documented at three layers** — Task 2 API docstring, Task 10 `replay_events` docstring, Task 14 user-facing doc. The message won't drift.
- **Cardinality safety is tested, not just documented** — Task 1 classifies attributes into `BOUNDED_ATTRS`/`UNBOUNDED_ATTRS`, Task 6 tests that `run_id` never leaks into a span name, Task 14 publishes the budget table. Rare to see this discipline applied.
- **Disabled-path overhead budget encoded as an assertion** (Task 13 `otel-disabled-overhead`): `<1ms/stage` and `no opentelemetry.* imports` are both checked — directly maps to spec success criterion §11.4.
- **Version bump and `CLAUDE.md` line-5 edit paired with the deletion commit** (Task 18). Prevents the stale-version-in-docs drift seen in earlier phases.

---

## Relevant Files

- Plan: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-09-otel-genai-semconv-plan.md`
- Spec: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-09-otel-genai-semconv-design.md`
- Spec review: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-09-otel-genai-semconv-spec-review.md`
- Phase 02 dependency: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-02-cross-platform-python-hooks-design.md`
- Legacy exporter (to delete in Task 18): `/Users/denissajnar/IdeaProjects/forge/shared/forge-otel-export.sh`
- Observability doc (rewritten in Task 14): `/Users/denissajnar/IdeaProjects/forge/shared/observability.md`
- Orchestrator (updated in Task 15): `/Users/denissajnar/IdeaProjects/forge/agents/fg-100-orchestrator.md`
- PREFLIGHT constraints (appended in Task 16): `/Users/denissajnar/IdeaProjects/forge/shared/preflight-constraints.md`
- Plugin manifest (version bump + extras in Tasks 16 + 18): `/Users/denissajnar/IdeaProjects/forge/plugin.json`
