# PREFLIGHT Constraints

Validation rules enforced during PREFLIGHT stage. Referenced from CLAUDE.md.

- Scoring: `critical_weight >= 10`, `warning_weight >= 1 > info_weight >= 0`, `pass_threshold >= 60`, `concerns_threshold >= 40`, gap >= 10, `oscillation_tolerance` 0-20. `total_retries_max` 5-30.
- Convergence: `max_iterations` 3-20, `plateau_threshold` 0-10, `plateau_patience` 1-5, `target_score` in [pass_threshold, 100].
- Sprint: `sprint.poll_interval_seconds` 10-120 (default 30), `sprint.dependency_timeout_minutes` 5-180 (default 60).
- Tracking: `tracking.archive_after_days` 30-365 or 0 (default 90).
- Scope: `decomposition_threshold` 2-10 (default 3). Routing: `vague_threshold` low/medium/high (default medium).
- Shipping: `min_score` in [pass_threshold, 100] (default 90), `evidence_max_age_minutes` 5-60 (default 30).
- Model routing: `model_routing.default_tier` must be `fast`, `standard`, or `premium`. Agent IDs in overrides validated against `agent-registry.md`.
- Implementer inner loop: `implementer.inner_loop.enabled` (boolean, default `true`), `implementer.inner_loop.max_fix_cycles` 1-5 (default 3), `implementer.inner_loop.affected_test_cap` 5-50 (default 20).
- Confidence: `confidence.planning_gate` (boolean, default `true`), `confidence.autonomous_threshold` 0.3-0.95 (default 0.7), `confidence.pause_threshold` 0.1-0.7 (default 0.4), `confidence.initial_trust` 0.0-1.0 (default 0.5). `autonomous_threshold` must be > `pause_threshold` (gap >= 0.1). Weights must sum to 1.0 (+/- 0.01).
- Output compression: `output_compression.enabled` (boolean, default `true`), `output_compression.default_level` must be `verbose`, `standard`, `terse`, or `minimal` (default `terse`), `output_compression.per_stage` keys must match 10 stage names, `output_compression.auto_clarity` (boolean, default `true`).
- AI quality: `ai_quality.enabled` (boolean, default `true`), `ai_quality.categories` must be array of `AI-LOGIC`/`AI-PERF`/`AI-SEC`/`AI-CONCURRENCY`, `ai_quality.l1_patterns` (boolean, default `true`), `ai_quality.scout_learning` (boolean, default `true`), `ai_quality.severity_overrides` keys must match `AI-*` codes with values `CRITICAL`/`WARNING`/`INFO`. No PREFLIGHT failure -- all violations WARNING + fallback.
- Build graph: `build_graph.introspection` (boolean, default `true`), `build_graph.introspection_timeout_seconds` 10-300 (default 60), `build_graph.fallback` must be `heuristic` or `skip` (default `heuristic`), `build_graph.cache_enabled` (boolean, default `true`), `build_graph.module_boundary_discovery` (boolean, default `true`).
- Cost alerting: `cost_alerting.enabled` (boolean, default `true`), `cost_alerting.budget_ceiling_tokens` (integer, 0 or >= 10000, default 2000000), `cost_alerting.alert_thresholds` (array of 3 ascending floats in (0.0, 1.0), default [0.50, 0.75, 0.90]), `cost_alerting.per_stage_limits` (string `"auto"` or object with 10 stage keys, default `"auto"`), `cost_alerting.model_costs.*` (float > 0, see pricing table).
- Eval: `eval.suite` must be `lite`, `convergence`, `cost`, `compression`, or `smoke` (default `lite`). `eval.timeout_per_task_minutes` 5-120 (default 30). `eval.parallel_tasks` 1-5 (default 1). `eval.validation_timeout_seconds` 5-300 (default 60). `eval.regression_threshold_percent` 5-50 (default 20). `eval.keep_workdirs` (boolean, default `false`). `eval.model_override` must be `null`, `haiku`, `sonnet`, or `opus` (default `null`). No PREFLIGHT failure -- eval config is only used by `eval-runner.sh`, not by pipeline agents.
- Context guard: `context_guard.enabled` (boolean, default `true`), `context_guard.condensation_threshold` (integer, 5000-100000, default 30000), `context_guard.critical_threshold` (integer, must be > `condensation_threshold`, default 50000), `context_guard.max_condensation_triggers` (integer, 1-20, default 5). Cross-field: `critical_threshold` must be > `condensation_threshold`. On violation: WARNING, use `critical_threshold = condensation_threshold + 20000`.
- Compression eval: `compression_eval.enabled` (boolean, default `true`), `compression_eval.auto_run_after_compress` (boolean, default `false`), `compression_eval.drift_threshold_pct` 10-200 (default 50).

### Run History Store

| Field | Type | Default | Valid Range | Validation |
|-------|------|---------|-------------|------------|
| `run_history.enabled` | boolean | `true` | true/false | — |
| `run_history.retention_days` | integer | `365` | 30-3650 | WARN if <90 (losing trend data) |
| `run_history.optimize_interval` | integer | `10` | 1-100 | — |

### MCP Server

| Field | Type | Default | Valid Range | Validation |
|-------|------|---------|-------------|------------|
| `mcp_server.enabled` | boolean | `true` | true/false | — |
| `mcp_server.python_min_version` | string | `"3.10"` | Semver string | WARN if set below 3.10 |

### Playbook Self-Improvement

| Field | Type | Default | Valid Range | Validation |
|-------|------|---------|-------------|------------|
| `playbooks.auto_refine` | boolean | `false` | true/false | — |
| `playbooks.refine_min_runs` | integer | `3` | 2-20 | WARN if >10 (slow feedback loop) |
| `playbooks.refine_agreement` | float | `0.66` | 0.5-1.0 | WARN if <0.5 (low evidence bar) |
| `playbooks.max_auto_refines_per_run` | integer | `2` | 1-5 | — |
| `playbooks.rollback_threshold` | integer | `10` | 5-30 | — |
| `playbooks.max_rollbacks_before_reject` | integer | `2` | 1-5 | — |

**Cross-field:** If `auto_refine: true`, `refine_agreement` must be >= 0.66 (prevent low-confidence auto-changes).

## evals

Pipeline-level evaluation harness configuration. Validated at PREFLIGHT.

- `evals.enabled` must be `bool` (default `true`)
- `evals.composite_weights.pipeline_score` must be `float` in `[0, 1]`
- `evals.composite_weights.token_adherence` must be `float` in `[0, 1]`
- `evals.composite_weights.elapsed_adherence` must be `float` in `[0, 1]`
- sum of `evals.composite_weights.*` must equal `1.0` (tolerance ±0.01)
- `evals.regression_tolerance` must be `float` in `[0.0, 20.0]` (default `3.0`)
- `evals.baseline_branch` must be non-empty `str` (default `"master"`)
- `evals.scenario_timeout_seconds` must be `int` in `[60, 1800]` (default `900`)
- `evals.total_budget_seconds` must be `int` in `[60, 7200]` (default `2700`)
- `evals.total_budget_seconds` must be `>= evals.scenario_timeout_seconds`
- `evals.emit_overlap_metric` must be `bool` (default `true`)

Wall-clock contract (single source of truth — do not redefine elsewhere):
- Per-scenario hard cap: 900 s (15 min)
- Full-suite hard cap: 2700 s (45 min, with 50% headroom over target)
- Success-criterion target: ≤30 min p90 across 10 consecutive master runs (SC1)

## Prompt Injection Hardening (forge 3.1.0+)

**SEC-INJECTION-DISABLED halt.** If `forge-config.md` contains `security.untrusted_envelope.enabled: false` OR `security.injection_detection.enabled: false`, PREFLIGHT emits a `SEC-INJECTION-DISABLED` CRITICAL finding and halts the pipeline before any stage transition. These keys may only be set to `true`. Per-source tier overrides are permitted only if they *tighten* the tier (`silent → logged`, `logged → confirmed`, `confirmed → confirmed`); attempting to loosen a tier emits the same finding.

**Historical retro-scan.** On the first PREFLIGHT after upgrade to 3.1.0, if `.forge/wiki/` or `.forge/explore-cache.json` exists, the orchestrator runs them through `hooks/_py/mcp_response_filter.py` once. Any non-BLOCK findings are re-emitted as `SEC-INJECTION-HISTORICAL` INFO (informational only, does not halt). A sentinel file `.forge/security/.historical-scan-done` is written so the scan runs at most once per install.

**Filter availability.** PREFLIGHT MUST succeed importing `hooks/_py/mcp_response_filter.py`. A `ModuleNotFoundError` halts the pipeline with `SEC-INJECTION-DISABLED` because every external-data ingress depends on the filter.

## Implementer Reflection (Phase 04)

| Key | Type | Default | Range | Violation behavior |
|---|---|---|---|---|
| `implementer.reflection.enabled` | boolean | `true` | — | Non-boolean → log WARNING and default to `true`. |
| `implementer.reflection.max_cycles` | integer | `2` | `[1, 3]` | Out of range → log WARNING and clamp to default `2`. |
| `implementer.reflection.fresh_context` | boolean | `true` | — | Non-boolean → log WARNING and default to `true`. Setting to `false` opts into same-context critic (matches rejected Alt-A in spec §4.6 — discouraged). |
| `implementer.reflection.timeout_seconds` | integer | `90` | `[30, 180]` | Out of range → log WARNING and clamp to default `90`. On timeout per-dispatch: log INFO in stage notes, skip reflection for that task, continue to REFACTOR. Never blocks pipeline. |

**Resume rules:** On `/forge-recover resume`, PREFLIGHT must:
1. Reset `tasks[*].reflection_verdicts` to `[]` (stale mid-dispatch verdicts are not trustworthy).
2. Preserve `tasks[*].implementer_reflection_cycles` (budget is not refunded mid-task — prevents runaway retries after OS kill).
3. Preserve run-level `implementer_reflection_cycles_total` and `reflection_divergence_count`.

**Initialization:** At PREFLIGHT, for every task created at PLAN, set `implementer_reflection_cycles: 0` and `reflection_verdicts: []`. Set run-level `implementer_reflection_cycles_total: 0` and `reflection_divergence_count: 0`.
