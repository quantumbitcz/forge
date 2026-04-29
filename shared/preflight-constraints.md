# PREFLIGHT Constraints

Validation rules enforced during PREFLIGHT stage. Referenced from CLAUDE.md.

- Scoring: `critical_weight >= 10`, `warning_weight >= 1 > info_weight >= 0`, `pass_threshold >= 60`, `concerns_threshold >= 40`, gap >= 10, `oscillation_tolerance` 0-20. `total_retries_max` 5-30.
- Convergence: `max_iterations` 3-20, `plateau_threshold` 0-10, `plateau_patience` 1-5, `target_score` in [pass_threshold, 100].
- Sprint: `sprint.poll_interval_seconds` 10-120 (default 30), `sprint.dependency_timeout_minutes` 5-180 (default 60).
- Tracking: `tracking.archive_after_days` 30-365 or 0 (default 90).
- Scope: `decomposition_threshold` 2-10 (default 3). Routing: `vague_threshold` low/medium/high (default medium).
- Shipping: `min_score` in [pass_threshold, 100] (default 90), `evidence_max_age_minutes` 5-60 (default 30).
- Model routing: `model_routing.default_tier` must be `fast`, `standard`, or `premium`. Agent IDs in overrides validated against `agents.md#registry`.
- Implementer inner loop: `implementer.inner_loop.enabled` (boolean, default `true`), `implementer.inner_loop.max_fix_cycles` 1-5 (default 3), `implementer.inner_loop.affected_test_cap` 5-50 (default 20).
- Confidence: `confidence.planning_gate` (boolean, default `true`), `confidence.autonomous_threshold` 0.3-0.95 (default 0.7), `confidence.pause_threshold` 0.1-0.7 (default 0.4), `confidence.initial_trust` 0.0-1.0 (default 0.5). `autonomous_threshold` must be > `pause_threshold` (gap >= 0.1). Weights must sum to 1.0 (+/- 0.01).
- Output compression: `output_compression.enabled` (boolean, default `true`), `output_compression.default_level` must be `verbose`, `standard`, `terse`, or `minimal` (default `terse`), `output_compression.per_stage` keys must match 10 stage names, `output_compression.auto_clarity` (boolean, default `true`).
- AI quality: `ai_quality.enabled` (boolean, default `true`), `ai_quality.categories` must be array of `AI-LOGIC`/`AI-PERF`/`AI-SEC`/`AI-CONCURRENCY`, `ai_quality.l1_patterns` (boolean, default `true`), `ai_quality.scout_learning` (boolean, default `true`), `ai_quality.severity_overrides` keys must match `AI-*` codes with values `CRITICAL`/`WARNING`/`INFO`. No PREFLIGHT failure -- all violations WARNING + fallback.
- Build graph: `build_graph.introspection` (boolean, default `true`), `build_graph.introspection_timeout_seconds` 10-300 (default 60), `build_graph.fallback` must be `heuristic` or `skip` (default `heuristic`), `build_graph.cache_enabled` (boolean, default `true`), `build_graph.module_boundary_discovery` (boolean, default `true`).
- Cost alerting: `cost_alerting.enabled` (boolean, default `true`), `cost_alerting.budget_ceiling_tokens` (integer, 0 or >= 10000, default 2000000), `cost_alerting.alert_thresholds` (array of 3 ascending floats in (0.0, 1.0), default [0.50, 0.75, 0.90]), `cost_alerting.per_stage_limits` (string `"auto"` or object with 10 stage keys, default `"auto"`), `cost_alerting.model_costs.*` (float > 0, see pricing table).
- Eval: `eval.suite` must be `lite`, `convergence`, `cost`, `compression`, or `smoke` (default `lite`). `eval.timeout_per_task_minutes` 5-120 (default 30). `eval.parallel_tasks` 1-5 (default 1). `eval.validation_timeout_seconds` 5-300 (default 60). `eval.regression_threshold_percent` 5-50 (default 20). `eval.keep_workdirs` (boolean, default `false`). `eval.model_override` must be `null`, `haiku`, `sonnet`, or `opus` (default `null`). No PREFLIGHT failure -- eval config is only used by `eval-runner.sh`, not by pipeline agents.
- Context guard: `context_guard.enabled` (boolean, default `true`), `context_guard.condensation_threshold` (integer, 5000-100000, default 30000), `context_guard.critical_threshold` (integer, must be > `condensation_threshold`, default 50000), `context_guard.max_condensation_triggers` (integer, 1-20, default 5). Cross-field: `critical_threshold` must be > `condensation_threshold`. On violation: WARNING, use `critical_threshold = condensation_threshold + 20000`.
- Compression eval: `compression_eval.enabled` (boolean, default `true`), `compression_eval.auto_run_after_compress` (boolean, default `false`), `compression_eval.drift_threshold_pct` 10-200 (default 50).
- BRAINSTORMING: `brainstorm.enabled` (boolean, default `true`); `brainstorm.spec_dir` (string, default `docs/superpowers/specs/`, parent directory must exist or be creatable — write probe at PREFLIGHT); `brainstorm.autonomous_extractor_min_confidence` must be one of `low | medium | high` (default `medium`); `brainstorm.transcript_mining.enabled` (boolean, default `true`); `brainstorm.transcript_mining.top_k` integer in [1, 10] (default 3); `brainstorm.transcript_mining.max_chars` integer in [500, 32000] (default 4000). All keys go in the `<!-- locked -->` block — not subject to retrospective auto-tuning.
- Cross-reviewer consistency: `quality_gate.consistency_promotion.enabled` (boolean, default `true`); `quality_gate.consistency_promotion.threshold` integer in [2, 9] (default 3).
- Bug investigator: `bug.hypothesis_branching.enabled` (boolean, default `true`); `bug.fix_gate_threshold` float in [0.50, 0.95] (default 0.75 — "almost perfect code" gate; only hypotheses above this posterior satisfy the fix gate).
- Post-run defense: `post_run.defense_enabled` (boolean, default `true`); `post_run.defense_min_evidence` (boolean, default `true` — defense responses must reference at least one file path or commit SHA when set).
- PR builder: `pr_builder.default_strategy` must be one of `open-pr | open-pr-draft | direct-push | stash` (default `open-pr-draft` — autonomous lands as draft for explicit human promotion; `abandon` is interactive-only, never an autonomous default); `pr_builder.cleanup_checklist_enabled` (boolean, default `true`).
- Worktree hygiene: `worktree.stale_after_days` integer in [1, 365] (default 30 — worktrees older than this are flagged `WORKTREE-STALE`).
- Platform detection: `platform.detection` must be one of `auto | github | gitlab | bitbucket | gitea` (default `auto` — detect via remote URL + repo files); `platform.remote_name` non-empty string matching `^[a-zA-Z0-9_./-]+$` (default `origin` — git remote to inspect when `platform.detection == auto`).

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

### Judge loop bounds

- `plan_judge_loops <= 2` — enforced by orchestrator; violation is a PREFLIGHT error.
- `impl_judge_loops[<task_id>] <= 2` for every known task.
- `judge_verdicts[].judge_id in {"fg-205-plan-judge", "fg-301-implementer-judge"}`.

## Speculation

PREFLIGHT validates the `speculation:` block:

- `candidates_max in [2,5]` — invalid raises `CONFIG-SPECULATION-CANDIDATES` CRITICAL.
- `auto_pick_threshold_delta in [1,20]` — invalid raises `CONFIG-SPECULATION-DELTA` CRITICAL.
- `token_ceiling_multiplier in [1.5, 4.0]` — invalid raises `CONFIG-SPECULATION-CEILING` CRITICAL.
- `min_diversity_score in [0.05, 0.50]` — invalid raises `CONFIG-SPECULATION-DIVERSITY` CRITICAL.
- `emphasis_axes length >= candidates_max` — invalid raises `CONFIG-SPECULATION-AXES` CRITICAL.

Any CRITICAL fails PREFLIGHT with `preflight_failed = true`.

## Consistency voting (forge 3.1.0+)

PREFLIGHT validates the `consistency:` block:

| Field | Rule | Violation handling |
|---|---|---|
| `consistency.enabled` | must be boolean | PREFLIGHT fails with CRITICAL |
| `consistency.n_samples` | must be odd integer in `[1, 9]` | PREFLIGHT fails with CRITICAL; `n_samples=1` logged as WARNING (voting effectively disabled) |
| `consistency.decisions` | must be a subset of `{shaper_intent, validator_verdict, pr_rejection_classification}` in 3.1.0 | PREFLIGHT fails with CRITICAL on unknown entry |
| `consistency.model_tier` | must be one of the tiers declared in `model_routing.tiers` | PREFLIGHT fails with CRITICAL |
| `consistency.cache_enabled` | must be boolean | PREFLIGHT fails with CRITICAL |
| `consistency.min_consensus_confidence` | float in `[0.0, 1.0]` | PREFLIGHT fails with CRITICAL on out-of-range |

See `shared/consistency/voting.md` for the dispatch contract, aggregation algorithm, and cost delta table.

## `observability.otel.*` (forge 3.4.0+)

| Parameter                                       | Type / Range          | Default           |
|-------------------------------------------------|-----------------------|-------------------|
| `observability.otel.enabled`                    | bool                  | `false`           |
| `observability.otel.endpoint`                   | non-empty when enabled| `""`              |
| `observability.otel.exporter`                   | `grpc`\|`http`\|`console` | `grpc`        |
| `observability.otel.service_name`               | non-empty string      | `forge-pipeline`  |
| `observability.otel.sample_rate`                | float in `[0.0, 1.0]` | `1.0`             |
| `observability.otel.openinference_compat`       | bool                  | `false`           |
| `observability.otel.include_tool_spans`         | bool                  | `false`           |
| `observability.otel.batch_size`                 | int in `[1, 1024]`    | `32`              |
| `observability.otel.flush_interval_seconds`     | int in `[1, 60]`      | `2`               |

Violations log WARNING and fall back to defaults. When `enabled=true` but `opentelemetry-api` is not importable, WARNING + disable OTel for the run (pipeline continues — emission is best-effort; `otel.replay()` remains authoritative via `.forge/events.jsonl`). See `shared/observability.md` for the durability contract and sampler semantics.

## Repo-map prompt compaction

**Rule:** `code_graph.prompt_compaction.enabled: true` requires `code_graph.enabled: true`. If `code_graph.prompt_compaction.enabled: true`, then `code_graph.enabled: true` MUST also hold.

**Rationale:** The repo-map ranker reads `.forge/code-graph.db`; disabling the graph while enabling compaction yields permanent degraded packs and hides graph-build misconfiguration.

**PREFLIGHT action when violated:** Emit CRITICAL `CONFIG-PROMPT-COMPACTION-REQUIRES-GRAPH`, halt with message:

> "code_graph.prompt_compaction.enabled is true but code_graph.enabled is false. Enable the graph or set prompt_compaction.enabled: false."

**Defaults snapshot:**

- `prompt_compaction.enabled: false` (opt-in)
- `top_k: 25`
- `token_budget: 8000`
- `recency_window_days: 30`
- `min_slice_tokens: 400`
- `recency_boost_max: 1.5`
- `keyword_overlap_cap: 5`
- `cache_max_entries: 16`
- `min_nodes_for_rank: 50`
- `edge_weights: {CALLS:1.0, REFERENCES:1.0, IMPORTS:0.7, INHERITS:0.8, IMPLEMENTS:0.8, TESTS:0.4, CONTAINS:0.3}`

## Handoff

| Parameter | Range | Default | Rationale |
|---|---|---|---|
| `handoff.enabled` | bool | `true` | Master toggle |
| `handoff.soft_threshold_pct` | 30-80 | `50` | Below 30 → noise storm; above 80 → overlaps with hard |
| `handoff.hard_threshold_pct` | `soft + 10` to 95 | `70` | Must exceed soft by margin; max 95 leaves recovery room |
| `handoff.min_interval_minutes` | 1-60 | `15` | Prevents handoff storm in fast pipelines |
| `handoff.autonomous_mode` | `auto` \| `milestone_only` \| `disabled` | `auto` | Enumerated; controls autonomous write frequency |
| `handoff.auto_on_ship` | bool | `true` | Always write terminal handoff on SHIP |
| `handoff.auto_on_escalation` | bool | `true` | Write handoff when `feedback_loop_count >= 2` |
| `handoff.chain_limit` | 5-500 | `50` | Rotation cap per run |
| `handoff.auto_memory_promotion` | bool | `true` | Terminal handoffs push top PREEMPTs to user auto-memory |
| `handoff.mcp_expose` | bool | `true` | Expose handoffs via F30 MCP server |

## Cost Governance (Phase 6)

All validations run at PREFLIGHT. Any CRITICAL aborts the run; WARNING logs and proceeds.

| Field | Rule | Severity on violation |
|---|---|---|
| `cost.ceiling_usd` | float >= 0 | CRITICAL if negative |
| `cost.ceiling_usd` | warn if 0 < x < 1.00 (likely typo) | WARNING |
| `cost.warn_at` | 0 < x < 1 | CRITICAL |
| `cost.throttle_at` | 0 < x < 1 | CRITICAL |
| `cost.abort_at` | 0 < x <= 1 | CRITICAL |
| ordering | `warn_at < throttle_at <= abort_at` | CRITICAL |
| `cost.aware_routing` | boolean | CRITICAL if non-bool |
| `cost.aware_routing: true` requires `model_routing.enabled: true` | otherwise CRITICAL |
| `cost.tier_estimates_usd.fast/standard/premium` | float > 0 | CRITICAL if <= 0 or missing |
| tier ratio | warn if `premium / fast > 200` | WARNING |
| `cost.conservatism_multiplier.fast/standard/premium` | float >= 1.0 | CRITICAL if < 1.0 |
| multiplier sanity | warn if any multiplier > 10.0 | WARNING |
| `cost.pinned_agents[]` | each must match agents.md#registry | WARNING for unknown IDs |
| `cost.skippable_under_cost_pressure[]` | each must match agents.md#registry | WARNING for unknown IDs |
| `cost.skippable_under_cost_pressure[]` | MUST NOT contain any SAFETY_CRITICAL agent | CRITICAL |

**Implementation note:** PREFLIGHT calls `shared/config_validator.py` which reads the above rules from this section. The SAFETY_CRITICAL cross-check imports `cost_governance.SAFETY_CRITICAL` (single source of truth).

## intent_verification (Phase 7 F35)

- `intent_verification.enabled` — boolean; default `true`.
- `intent_verification.strict_ac_required_pct` — integer 50-100; default `100`.
- `intent_verification.max_probes_per_ac` — integer 1-200; default `20`.
- `intent_verification.probe_timeout_seconds` — integer 5-300; default `30`.
- `intent_verification.probe_tier` — integer in {1, 2, 3}; default `2`.
- `intent_verification.allow_runtime_probes` — boolean; default `true`.
- `intent_verification.forbidden_probe_hosts` — list of glob patterns; default
  `["*.prod.*", "*.production.*", "*.live.*", "*.amazonaws.com",
    "*.googleusercontent.com", "10.*", "172.16.*-172.31.*", "192.168.*"]`.

PREFLIGHT FAIL (CRITICAL) if `probe_tier == 3` and
`infra.max_verification_tier < 3`.

## impl_voting (Phase 7 F36)

- `impl_voting.enabled` — boolean; default `true`.
- `impl_voting.trigger_on_confidence_below` — float 0.0-1.0; default `0.4`;
  **must be <= `confidence.pause_threshold`** (PREFLIGHT FAIL CRITICAL otherwise).
- `impl_voting.trigger_on_risk_tags` — list of strings from
  {"high","data-mutation","auth","payment","concurrency","migration","bugfix"};
  default `["high"]`. Unknown tags -> WARNING at PREFLIGHT, not FAIL.
- `impl_voting.trigger_on_regression_history_days` — integer 0-365; default `30`.
- `impl_voting.samples` — **exactly 2** (future-reserved; any other value is
  PREFLIGHT FAIL CRITICAL).
- `impl_voting.tiebreak_required` — boolean; default `true`.
- `impl_voting.skip_if_budget_remaining_below_pct` — integer 0-100; default `30`.
