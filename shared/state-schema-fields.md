# State Schema — Field Reference

> **Overview:** see [`state-schema.md`](state-schema.md) for directory layout, top-level schema shape, atomic-write guarantees, and the concurrent-run lock.
>
> This document is the exhaustive field-by-field reference for `.forge/state.json`, plus the schemas of all related subsystem files (`security.injection_*` counters, `events.jsonl`, `checkpoint-{storyId}.json`, stage notes, feedback, reports, orchestrator input payload, `eval_run`, `prompt_compaction`, speculation fields) and the schema changelog.

## Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | string | Yes | Schema version string (`"1.10.0"`). Enables schema compatibility checks — the recovery engine checks this before parsing. If the version is missing, the state file is reinitialized. If the version is older, sequential migrations are applied (see [Version Migration](#version-migration)). v1.10.0 adds handoff tracking sub-object (handoff.last_written_at, handoff.last_path, handoff.chain, handoff.soft_triggers_this_run, handoff.hard_triggers_this_run, handoff.milestone_triggers_this_run, handoff.suppressed_by_rate_limit) for session handoff artifacts. v1.9.0 adds self-consistency voting counters (`consistency_cache_hits`, `consistency_votes.{shaper_intent,validator_verdict,pr_rejection_classification}`). v1.8.0 adds reflection counters (run-level `implementer_reflection_cycles_total`, `reflection_divergence_count`; task-level `tasks[*].implementer_reflection_cycles`, `tasks[*].reflection_verdicts`) for Chain-of-Verification critic. v1.7.0 adds `recovery_op` (orchestrator input payload) and `eval_run` (pipeline evaluation harness). v1.6.0 adds `recovery.circuit_breakers`, `critic_revisions`, `schema_version_history`. v1.5.0 adds `_seq` (write versioning), `previous_state` (for user_continue recovery), `convergence.diminishing_count`, `convergence.unfixable_info_count`. v1.4.0 adds optional `evidence` section for pre-ship verification tracking. v1.3.0 adds optional `decomposition` section and `visual_companion` integration. v1.2.0 adds the optional `graph` section for graph update state tracking. v1.1.0 added optional tracking fields. |
| `_seq` | integer | Yes | Monotonic write counter. Starts at 1. Incremented on every write by `forge-state-write.sh`. Used for stale write detection. |
| `complete` | boolean | Yes | `false` while pipeline is running, `true` when Stage 9 finishes successfully. Used by PREFLIGHT to detect interrupted runs. |
| `story_id` | string | Yes | Kebab-case identifier for the current story. Derived from the requirement at PREFLIGHT (e.g., `"feat-plan-comments"`, `"fix-client-404"`, `"refactor-booking-validation"`). Used as suffix for checkpoint and notes files. |
| `requirement` | string | Yes | The original user requirement, verbatim. Captured from the `/forge-run` invocation argument. |
| `domain_area` | string | Yes | Primary domain area affected by this change. Detected by the planner at Stage 2 using the algorithm in `shared/domain-detection.md`. Known domains: `auth`, `billing`, `user`, `scheduling`, `communication`, `inventory`, `workflow`, `commerce`, `search`, `analytics`, `config`, `api`, `infra`, `general`. Falls back to `"general"` if detection produces no clear result or the planner fails to set it (orchestrator emits WARNING). Immutable after Stage 2. Used by PREEMPT decay, auto-tuning, and bug hotspot tracking. |
| `risk_level` | string | Yes | Risk assessment from the planner. Valid values: `"LOW"`, `"MEDIUM"`, `"HIGH"`. Set at Stage 2, used at Stage 3 for the auto-proceed decision gate. |
| `story_state` | string | Yes | The overall pipeline state — the highest active stage across all components. If backend is IMPLEMENTING and frontend is EXPLORING, the top-level story_state is IMPLEMENTING. Valid values and transitions defined below. Updated at the start of each stage. |
| `previous_state` | string | Yes | Pipeline state before the last transition. Set by `forge-state.sh` on every transition. Used by `user_continue` (E5) to resume from escalation. Empty string `""` initially. |
| `active_component` | string | Yes | The component the orchestrator is currently processing. Set before dispatching agents for a component's tasks. Used by the check engine to route rules. Example: `"backend"`. |
| `components` | object | Yes | Per-component state tracking for monorepo and multi-stack projects. Keys are derived from `forge.local.md` config: for single-component projects, the key is the component name from config (e.g., `"backend"`); for multi-component projects with `path:` fields, keys are the component names (e.g., `"backend"`, `"frontend"`, `"mobile"`). The top-level `story_state` is always the highest active stage across all components. Values are component state objects. See the [components section](#components-object-required) below. |
| `quality_cycles` | integer | Yes | Number of quality review cycles completed in Stage 6 (REVIEW). Starts at 0, incremented each time the quality gate dispatches fixes and rescores. Max is `quality_gate.max_review_cycles` from config. |
| `test_cycles` | integer | Yes | Number of test fix cycles completed in Stage 5 Phase B (test gate). Starts at 0, incremented each time failing tests are dispatched to the implementer. Max is `test_gate.max_test_cycles` from config. |
| `verify_fix_count` | integer | Yes | Number of build/lint fix attempts in Stage 5 Phase A. Starts at 0, incremented on each compile or lint failure that triggers an auto-fix. Checked by the convergence engine BEFORE dispatching another IMPLEMENT — when `verify_fix_count >= implementation.max_fix_loops` (default: 3), the orchestrator escalates instead of retrying. This is the Phase A inner cap, distinct from `test_cycles` (Phase 1B) and `quality_cycles` (Phase 2). |
| `validation_retries` | integer | Yes | Number of REVISE verdicts received at Stage 3 (VALIDATE). Starts at 0, incremented when the validator returns REVISE and the planner revises the plan. Max is `validation.max_validation_retries` from config (default: 2). |
| `total_retries` | integer | Yes | Cumulative retry count across all loops (validation_retries + verify_fix_count + test_cycles + quality_cycles + direct PR rejection increments). Used for the global retry budget. Starts at 0, incremented on every retry anywhere in the pipeline. |
| `total_retries_max` | integer | Yes | Global retry ceiling. Default: 10. Configurable in `forge-config.md`. When `total_retries >= total_retries_max`, the orchestrator escalates regardless of individual loop budgets. Constraint: >= 5 and <= 30. |
| `playbook_pre_refine_version` | string | No | Playbook version before auto-refinement was applied at PREFLIGHT. Set by orchestrator when `playbooks.auto_refine: true` triggers. Used by retrospective (fg-700) to detect rollback-worthy regressions. Null if no auto-refinement occurred. |
| `implementer_fix_cycles` | integer | Yes | Total inner-loop fix cycles across all tasks in this run. Tracked separately from convergence engine counters (`verify_fix_count`, `test_cycles`, `quality_cycles`, `total_iterations`, `total_retries`). Does NOT feed into `total_retries`. Starts at 0, incremented by the implementer's inner-loop validation (section 5.4.1 of fg-300). |
| `inner_loop` | object | Yes | Inner-loop validation state for the implementer. Tracks per-run metrics for lint and affected test execution within Stage 4. Initialized at PREFLIGHT with all counters at 0. |
| `inner_loop.enabled` | boolean | Yes | Whether inner-loop validation is active for this run. Mirrors `implementer.inner_loop.enabled` from config. Default: `true`. |
| `inner_loop.fix_cycles_used` | integer | Yes | Total inner-loop fix cycles consumed across all tasks. Mirrors top-level `implementer_fix_cycles` (canonical counter). Kept for convenience when reading the `inner_loop` object in isolation. |
| `inner_loop.fix_cycles_max` | integer | Yes | Per-task fix cycle budget. From `implementer.inner_loop.max_fix_cycles` config. Default: 3. Range: 1-5. |
| `inner_loop.tasks_total` | integer | Yes | Total tasks processed through the inner loop in this run. |
| `inner_loop.tasks_with_fixes` | integer | Yes | Number of tasks that required at least one inner-loop fix cycle. |
| `inner_loop.lint_fixes` | integer | Yes | Fix cycles spent on lint issues across all tasks. |
| `inner_loop.test_fixes` | integer | Yes | Fix cycles spent on test failures across all tasks. |
| `inner_loop.tests_run` | integer | Yes | Total number of affected test files executed by the inner loop. |
| `inner_loop.tests_passed` | integer | Yes | Number of affected test files that passed. |
| `inner_loop.lint_issues_fixed` | integer | Yes | Total lint issues fixed by the inner loop across all tasks. |
| `inner_loop.remaining_issues` | array | Yes | Issues that exhausted the inner-loop budget (passed to VERIFY). Each entry: `{ "task": "<name>", "type": "lint"\|"test", "detail": "<description>" }`. Empty array when all issues resolved. |
| `check_engine` | object | Yes | L0 check engine metrics for the run. Populated from `.forge/.l0-*` counter files by the orchestrator at stage transitions. |
| `check_engine.l0_blocks` | integer | Yes | Number of edits blocked by L0 syntax validation. Higher counts may indicate the implementer is producing poor syntax. |
| `check_engine.l0_total_checks` | integer | Yes | Total number of L0 syntax checks performed this run. |
| `check_engine.l0_skipped` | integer | Yes | Number of L0 checks skipped (tree-sitter unavailable, language unsupported, timeout). |
| `check_engine.l0_avg_latency_ms` | number | Yes | Average L0 check latency in milliseconds. Should be <500ms; higher values indicate tree-sitter performance issues. |
| `evidence_refresh_count` | integer | Yes | Tracks stale-evidence refresh attempts at SHIPPING entry. Starts at 0, capped at 3 before user escalation. See `verification-evidence.md` §Staleness and `state-transitions.md` row 52. |
| `stage_timestamps` | object | Yes | Map of stage name (lowercase) to ISO 8601 timestamp marking when that stage started. Keys are: `"preflight"`, `"explore"`, `"plan"`, `"validate"`, `"implement"`, `"verify"`, `"review"`, `"docs"`, `"ship"`, `"learn"`. Only stages that have started appear in the map. |
| `last_commit_sha` | string | Yes | Git commit SHA of the most recent forge-created commit. Set after the pre-implement checkpoint commit (Stage 4) and updated after the final commit (Stage 8). Used by PREFLIGHT to detect git drift on interrupted-run recovery. Empty string `""` before the first commit. |
| `preempt_items_applied` | string[] | Yes | List of PREEMPT item identifiers from `forge-log.md` that were loaded at PREFLIGHT for the current domain area. Records what was *loaded*, not what was *used*. Empty array `[]` if no items match. |
| `preempt_items_status` | object | Yes | Tracks actual usage of PREEMPT items during implementation. Keys are item identifiers. Values: `{ "applied": true, "false_positive": false }` (item used and relevant), `{ "applied": false, "false_positive": true }` (item loaded but inapplicable). Populated by orchestrator from agent stage notes. Read by retrospective to update hit counts and confidence decay in `forge-log.md`. |
| `learnings_cache` | object\|null | No | Per-run cache of `LearningItem` records loaded from `shared/learnings/` and `~/.claude/forge-learnings/` by `learnings_io.load_all()` at the first dispatch that needs injection (orchestrator §0.6.1). Populated lazily on first use; reused by every subsequent dispatch within the same run. The orchestrator selects per-agent subsets from this cache via `learnings_selector.select_for_dispatch()`; unused items remain in the cache but are never injected. The schema mirrors the `LearningItem` dataclass in `hooks/_py/learnings_selector.py` (`id`, `source_path`, `body`, `base_confidence`, `confidence_now`, `half_life_days`, `applied_count`, `last_applied`, `applies_to`, `domain_tags`, `archived`). Cleared at LEARN stage completion so the next run reloads after retrospective write-back. `null` (or absent) before the first injection-eligible dispatch. Survives `/forge-recover reset` only if the run completes — otherwise the next run rebuilds it on first dispatch (no on-disk persistence beyond `state.json`). |
| `feedback_classification` | string | Yes | Feedback type from the most recent PR rejection. Valid values: `""` (no feedback), `"implementation"` (code-level feedback → re-enter Stage 4), `"design"` (design-level feedback → re-enter Stage 2). Set by orchestrator after reading `fg-710-post-run` stage notes. |
| `previous_feedback_classification` | string | Yes | Feedback type from the preceding PR rejection. Used by the orchestrator to detect feedback loops — when `feedback_classification == previous_feedback_classification` for 2+ consecutive rejections, the orchestrator escalates. Updated by the orchestrator before comparing classifications. Empty string `""` initially. |
| `feedback_loop_count` | integer | Yes | Consecutive PR rejections with the same `feedback_classification`. Starts at 0, incremented on each rejection where classification matches `previous_feedback_classification`. Reset to 0 when classification changes. When `>= 2`, the orchestrator escalates with a feedback loop warning (see `stage-contract.md` Stage 8 and `fg-100-orchestrator.md` User Response section). |
| `score_history` | number[] | Yes | Unified quality score per review cycle for oscillation detection across all components. Appended after each quality gate scoring with the aggregate (unified) score. Used to detect regressions: if score drops by more than `oscillation_tolerance` between consecutive cycles, the orchestrator escalates. In multi-component projects, per-component score histories are tracked within `components[key].score_history` — see the components section below. Oscillation detection runs on BOTH the unified history and per-component histories (a per-component regression masked by other component improvements triggers a WARNING). Integer with default scoring weights; may be non-integer with custom weights. |
| `convergence` | object | Yes | Convergence engine state. Tracks two-phase iteration progress (correctness → perfection → safety gate). See `shared/convergence-engine.md` for full algorithm. Initialized at PREFLIGHT with all counters at 0. |
| `convergence.phase` | string | Yes | Current convergence phase. Valid values: `"correctness"` (Phase 1 — IMPLEMENT ↔ VERIFY), `"perfection"` (Phase 2 — IMPLEMENT ↔ REVIEW), `"safety_gate"` (final VERIFY after Phase 2). Transitions managed by the convergence engine. |
| `convergence.phase_iterations` | integer | Yes | Iteration count within the current phase. Resets to 0 on phase transition. |
| `convergence.total_iterations` | integer | Yes | Cumulative iteration count across all phases. Never resets. Feeds into `total_retries` budget — each increment also increments `total_retries`. |
| `convergence.plateau_count` | integer | Yes | Consecutive Phase 2 cycles where score improved by <= `plateau_threshold`. Resets to 0 on any improvement > `plateau_threshold`. When >= `plateau_patience`, convergence is declared. |
| `convergence.last_score_delta` | number | Yes | Score change from the previous cycle (`current_score - previous_score`). 0 on first cycle. Used for convergence state classification. May be non-integer with custom scoring weights. |
| `convergence.convergence_state` | string | Yes | Current convergence classification. Valid values: `"IMPROVING"` (score increasing meaningfully), `"PLATEAUED"` (score stalled — convergence declared), `"REGRESSING"` (score dropped beyond tolerance — escalate). |
| `convergence.phase_history` | array | Yes | Append-only log of completed phases within a single run. Each entry: `{ "phase": "<name>", "iterations": <int>, "outcome": "converged"\|"escalated"\|"restarted", "duration_seconds": <int> }`. Outcome values: `"converged"` (target reached or plateau accepted), `"escalated"` (cap hit, regression, or user escalation), `"restarted"` (safety gate failure triggered correctness restart). Used by retrospective for trend analysis. **Trimming:** Capped at 50 entries per run. With `max_iterations` capped at 20 and a maximum of 2 safety gate restarts, the theoretical maximum is ~44 entries — the cap provides headroom without unbounded growth. Trimmed entries are summarized in the retrospective report. Resets to `[]` at PREFLIGHT for each new run. |
| `convergence.safety_gate_passed` | boolean | Yes | `true` when the final VERIFY after Phase 2 passes. `false` until then. If safety gate fails, phase transitions back to correctness and this resets to `false`. |
| `convergence.safety_gate_failures` | integer | Yes | Consecutive safety gate failures. When >= 2, the orchestrator escalates immediately (cross-phase oscillation detected — Phase 2 fixes keep breaking tests). Resets to 0 on safety gate pass. Default: 0. |
| `convergence.unfixable_findings` | array | Yes | Findings that survived all iterations with documented rationale. Each entry: `{ "category": "<CATEGORY-CODE>", "file": "<path>", "line": <int>, "severity": "<CRITICAL\|WARNING\|INFO>", "reason": "<why not fixed>", "options": ["<option1>", "<option2>"] }`. Populated when Phase 2 converges below target. |
| `convergence.diminishing_count` | integer | Yes | Consecutive low-gain iterations (gain <= 2 points). Reset to 0 when gain > 2. Triggers `score_diminishing` event at 2. Default: 0. |
| `convergence.unfixable_info_count` | integer | Yes | INFO findings not fixed after first attempt. Used to compute effective_target. Default: 0. |
| `convergence.condensation` | object | Yes | Context condensation state for the current run. Tracks how many times the orchestrator condensed convergence loop context to reduce token consumption. See `shared/context-condensation.md`. Initialized at PREFLIGHT. |
| `convergence.condensation.count` | integer | Yes | Number of condensation operations performed in this run. Starts at 0, incremented each time the orchestrator condenses context between iterations. |
| `convergence.condensation.last_condensed_at_iteration` | integer\|null | Yes | Iteration number (`total_iterations`) at which the last condensation occurred. `null` before the first condensation. Used by the consecutive-condensation guard to prevent condensing on every iteration (minimum gap: 1 iteration). |
| `convergence.condensation.total_tokens_saved` | integer | Yes | Cumulative input tokens saved across all condensations in this run. Computed as `tokens_before_condensation - tokens_after_condensation` for each condensation. Default: 0. |
| `convergence.condensation.retained_tags` | string[] | Yes | Tag names that survived the most recent condensation (e.g., `["active_findings", "test_status", "acceptance_criteria"]`). Updated on each condensation. Default: `[]`. See `shared/context-condensation.md` for tag definitions. |
| `integrations` | object | Yes | Detected MCP integration availability. Populated at PREFLIGHT by probing for each MCP server. Each key is an integration name with an `available` boolean. The `linear` integration also includes a `team` string (Linear team key). The `neo4j` integration includes `last_build_sha` (SHA of the commit the graph was built from) and `node_count` (total nodes in the graph) — set by the `graph-init` skill; when available, the orchestrator pre-queries graph context at stage boundaries. Used by agents to conditionally use integrations (e.g., create Linear issues, post Slack messages). |
| `visual_companion` | boolean | No | Whether the superpowers visual companion is available. Detected at PREFLIGHT. Absent or `false` when superpowers plugin is not installed. |
| `linear` | object | Yes | Linear project management state for the current run. `epic_id`: Linear epic ID if the pipeline run is tracked as an epic (empty string if Linear unavailable). `story_ids`: array of Linear issue IDs created for pipeline stories. `task_ids`: map of task ID (e.g., `"T001"`) to Linear sub-issue ID. Populated during PLAN and IMPLEMENT stages. |
| `modules` | object[] | Yes | **Distinct from `components`.** Per-module state for cross-repo multi-module projects (different git repos with different frameworks). Each entry: `{ "module": "spring", "story_state": "IMPLEMENTING", "story_id": "story-1" }`. `"FAILED"` and `"BLOCKED"` are module-only states (see below). Blocked modules include `blocked_by`. The orchestrator manages transitions: backend modules complete through VERIFY before frontend enters IMPLEMENT. Empty array for single-module projects. **Relationship to `components`:** `components` tracks per-service state within a single monorepo (same git repo, potentially different frameworks). `modules` tracks per-repo state across related repositories. A monorepo uses `components`; a multi-repo architecture uses `modules`. Both can be active simultaneously (e.g., a monorepo backend component with a cross-repo mobile frontend module). |
| `cost` | object | Yes | Pipeline run cost tracking. `wall_time_seconds`: total elapsed wall-clock time from PREFLIGHT start to current stage (updated at each stage transition). `stages_completed`: count of stages that have finished (0-10). `estimated_cost_usd`: estimated USD cost based on token consumption and model pricing. Used by the retrospective for trend analysis and by the orchestrator for timeout detection. |
| `cost.estimated_cost_usd` | number | — | Estimated USD cost based on token consumption and model pricing. Computed by `forge-token-tracker.sh` using approximate pricing: haiku ~$0.25/MTok input, sonnet ~$3/MTok input, opus ~$15/MTok input. Updated after each stage. Default: `0.0`. |
| `tokens` | object | No | Token usage tracking. Populated by `forge-token-tracker.sh` via orchestrator calls at stage boundaries. |
| `tokens.estimated_total` | integer | — | Cumulative estimated token usage (input + output) across all stages and agents. Updated by the `record` command. Default: 0. |
| `tokens.budget_ceiling` | integer | — | Maximum allowed token usage for the run. 0 means no limit. Configurable in `forge-config.md`. Default: 2000000. |
| `tokens.by_stage` | object | — | Per-stage token breakdown. Keys are stage names (e.g., `"explore"`, `"plan"`). Values: `{ "input": <int>, "output": <int> }`. Accumulates across multiple agent calls within a stage. |
| `tokens.by_agent` | object | — | Per-agent token breakdown. Keys are agent names (e.g., `"fg-200-planner"`). Values: `{ "input": <int>, "output": <int>, "dispatch_count": <int> }`. Accumulates across multiple calls to the same agent. `dispatch_count` tracks the number of times this agent was dispatched (used for cache estimation). |
| `tokens.budget_warning_issued` | boolean | — | `true` when `estimated_total >= 80%` of `budget_ceiling`. Prevents duplicate warnings. Default: `false`. |
| `tokens.model_distribution` | object | — | Model usage fractions. Keys are model names, values are usage fractions. Updated by `forge-token-tracker.sh` after each stage. Default: `{}`. |
| `tokens.model_fallbacks` | array | — | Fallback events when requested model was unavailable. Default: `[]`. |
| `tokens.condensation_savings` | integer | — | Total input tokens avoided by context condensation across all condensation operations. Computed as cumulative `tokens_before - tokens_after` for each condensation. Default: 0. See `shared/context-condensation.md`. |
| `tokens.condensation_count` | integer | — | Total number of condensation operations performed during the run. Derived from `convergence.condensation.count` (authoritative source). Written at stage transitions by the orchestrator. Default: 0. |
| `tokens.condensation_cost` | integer | — | Tokens consumed by the condensation LLM calls themselves (fast tier summarization input + output). Default: 0. |
| `tokens.effective_token_ratio` | float | — | `actual_tokens / (actual_tokens + condensation_savings)`. Lower is better — 0.6 means 40% of potential tokens were saved. 1.0 when no condensation occurred. Default: 1.0. |
| `tokens.compression_level_distribution` | object | — | Count of agent dispatches per compression verbosity level. Keys: `"verbose"`, `"standard"`, `"terse"`, `"minimal"`. Values: integer counts. Default: `{ "verbose": 0, "standard": 0, "terse": 0, "minimal": 0 }`. See `shared/output-compression.md`. |
| `tokens.output_tokens_per_agent` | object | — | Raw output token count per agent. Keys are agent IDs (e.g., `"fg-410"`). Values: integer token counts. Used by the retrospective to detect compression drift. Default: `{}`. |
| `build_graph` | object | No | Build system intelligence metrics. Written by `build-code-graph.sh` after cross-file edge resolution. |
| `build_graph.edges_total` | integer | — | Total number of IMPORTS edges in the code graph. Default: 0. |
| `build_graph.edges_resolved` | integer | — | Edges resolved via same-module or declared-dependency matching (confidence: `resolved`). Default: 0. |
| `build_graph.edges_module_inferred` | integer | — | Edges resolved via undeclared cross-module matching (confidence: `module-inferred`). Default: 0. |
| `build_graph.edges_heuristic` | integer | — | Edges resolved via heuristic basename matching (confidence: `heuristic`). Default: 0. |
| `build_graph.edges_unresolved` | integer | — | Import nodes with no matching target file. Default: 0. |
| `build_graph.resolution_accuracy` | float | — | Fraction of edges that are `resolved` or `module-inferred` (0.0-1.0). Higher is better. Default: 0.0. |
| `cost_alerting` | object | Yes | Budget alerting runtime state. Created by `cost-alerting.sh init` at PREFLIGHT. |
| `cost_alerting.enabled` | boolean | Yes | Whether cost alerting is active. Default: `true`. |
| `cost_alerting.thresholds` | float[] | Yes | Three ascending fractions [INFO, WARNING, CRITICAL]. Default: `[0.50, 0.75, 0.90]`. |
| `cost_alerting.per_stage_limits` | object | Yes | Token budget per stage. Auto-computed or explicit from config. Keys are lowercase stage names. |
| `cost_alerting.alerts_issued` | string[] | Yes | Alert levels already issued this run (deduplication). Possible values: `"INFO"`, `"WARNING"`, `"CRITICAL"`, `"EXCEEDED"`. |
| `cost_alerting.last_alert_level` | string | Yes | Most recent alert level. One of: `"OK"`, `"INFO"`, `"WARNING"`, `"CRITICAL"`, `"EXCEEDED"`. |
| `cost_alerting.routing_override` | object\|null | Yes | Temporary model routing override from cost downgrade. Null when not active. Keys are agent IDs, values are model tier strings. |
| `context` | object | Yes | Context degradation guard runtime state. Tracks context size metrics for quality protection. |
| `context.peak_tokens` | integer | Yes | Highest estimated context size observed in this run. Default: 0. |
| `context.condensation_triggers` | integer | Yes | Number of times the context guard forced condensation this run. Default: 0. |
| `context.per_stage_peak` | object | Yes | Peak context size per stage. Keys are lowercase stage names, values are integer token counts. |
| `context.last_estimated_tokens` | integer | Yes | Most recent context size estimate passed to `context-guard.sh check`. Default: 0. |
| `context.guard_checks` | integer | Yes | Total context guard checks performed this run. Default: 0. |
| `cost.per_stage` | object | Yes | Per-stage cost breakdown. Keys are stage names. Values: `{ "tokens": <int>, "cost_usd": <float>, "score_delta": <int\|null> }`. Stages without score impact have `score_delta: null`. Default: `{}`. |
| `cost.budget_remaining_tokens` | integer | Yes | Remaining token budget (`budget_ceiling - estimated_total`). 0 when no ceiling set. |
| `cost.efficiency_score` | float | Yes | Quality points gained per 100K tokens spent. Computed as `quality_delta / (tokens_spent / 100000)`. Default: 0.0. |
| `telemetry` | object | No | OpenTelemetry GenAI semconv observability state. Populated in-process by `hooks/_py/otel.py` (live) and reconstructible via `otel.replay()` from `.forge/events.jsonl` (authoritative). See `shared/observability.md` for the durability contract. |
| `telemetry.spans` | array | — | Append-only mirror of emitted spans for in-state audit (not the primary source of truth — spans live in OTLP/events.jsonl). Span attribute shape follows `shared/schemas/otel-genai-v1.json`. Capped at 500 entries per run. Default: `[]`. |
| `decision_quality` | object | No | Decision quality metrics for the current run. Populated by the quality gate and orchestrator. |
| `decision_quality.reviewer_agreement_rate` | float | — | Percentage of findings where multiple reviewers agreed on severity for the same `(file, line)`. 0.0 when no overlapping findings exist. Updated by `fg-400-quality-gate`. |
| `decision_quality.findings_with_low_confidence` | integer | — | Count of findings tagged with `confidence:LOW` or `confidence:MEDIUM`. Updated by `fg-400-quality-gate`. Default: 0. |
| `decision_quality.overridden_findings` | integer | — | Count of findings where the orchestrator pushed back or overrode a reviewer's recommendation. Default: 0. |
| `decision_quality.total_decisions_logged` | integer | — | Total number of entries in `.forge/decisions.jsonl` for this run. Updated at stage boundaries. Default: 0. |
| `recovery_budget` | object | Yes | Weighted recovery budget tracking. `total_weight`: sum of all applied strategy weights. `max_weight`: budget ceiling (default: 5.5). `applications[]`: list of `{ "strategy": "<name>", "weight": <float>, "stage": "<stage>", "timestamp": "<ISO8601>" }`. Strategy weights: transient-retry=0.5, tool-diagnosis=1.0, state-reconstruction=1.5, agent-reset=1.0, dependency-health=1.0, resource-cleanup=0.5, graceful-stop=0.0. When `total_weight >= max_weight`, escalate. When `total_weight >= 4.4` (80%), set `recovery.budget_warning_issued: true`. |
| `recovery` | object | Yes | Recovery engine runtime state. `total_failures`: count of error occurrences that triggered recovery evaluation. `total_recoveries`: count of successful recoveries. `degraded_capabilities`: list of capability names operating in degraded mode (e.g., `"linear"`, `"neo4j"`). `failures`: list of `{ "error_type": "<type>", "stage": "<stage>", "timestamp": "<ISO8601>", "strategy": "<strategy-applied>", "outcome": "recovered\|escalated" }`. `budget_warning_issued`: boolean, `true` when `recovery_budget.total_weight >= 4.4` (80% of budget). |
| `recovery.circuit_breakers` | object | No | Per-category circuit breaker state. Keys are failure categories (`build`, `test`, `network`, `agent`, `state`, `environment`). Values: `{ "state": "CLOSED\|OPEN\|HALF_OPEN", "failures_count": <int>, "last_failure_timestamp": "<ISO8601>\|null", "cooldown_seconds": 300, "flapping_count": <int>, "locked": <bool> }`. `flapping_count` (default 0): incremented when HALF_OPEN → OPEN (probe failed), reset to 0 on HALF_OPEN → CLOSED (probe succeeded). `locked` (default false): set to `true` when `flapping_count >= 3` — locked circuits remain OPEN indefinitely with no HALF_OPEN probes. Cleared by `/forge-recover repair`, `/forge-recover reset`, or new pipeline run; NOT cleared by `/forge-recover resume`. Only categories with at least one failure appear. Absent categories are implicitly CLOSED with `failures_count: 0`. See `shared/recovery/recovery-engine.md` section 8.1 for state machine, flapping detection, and category-to-error-type mapping. Default: `{}`. Added in v1.6.0. |
| `schema_version_history` | array | No | Append-only log of schema migrations applied to this state file. Each entry: `{ "from": "<version>", "to": "<version>", "timestamp": "<ISO8601>" }`. Capped at 20 entries (oldest trimmed). Added in v1.6.0. Default: `[]`. |
| `consistency_cache_hits` | integer | Yes | Count of self-consistency voting dispatch calls served from `.forge/consistency-cache.jsonl`. Incremented by `hooks/_py/consistency.py` on cache hit. Added in v1.9.0. Default: `0`. See `shared/consistency/voting.md`. |
| `consistency_votes` | object | Yes | Per-decision-point self-consistency voting counters. Keys: `shaper_intent`, `validator_verdict`, `pr_rejection_classification`. Each value is `{ "invocations": <int>, "cache_hits": <int>, "low_consensus": <int> }`. `invocations` increments on every dispatch (skipped on validator hard-verdict rule pass). `cache_hits` increments when a dispatch is served from cache. `low_consensus` increments when the winning label's mean confidence falls below `consistency.min_consensus_confidence` or when a `ConsistencyError` fires (too few samples survived parsing). Added in v1.9.0. Default: all counters `0`. See `shared/consistency/voting.md` §5 for fallback rules. |
| `linear_sync` | object | Yes | Tracks Linear API operation success/failure for desync detection. `in_sync`: boolean, true when all Linear operations succeeded. `failed_operations[]`: list of `{ "op": "<operation>", "error": "<message>", "timestamp": "<ISO8601>" }`. Read by retrospective to report desync. **Sync guarantees:** Linear operations are fire-and-forget with single retry — the pipeline does not block on Linear success. If `epic_id` is set but subsequent story/task creation fails, the orphaned epic remains in Linear (logged in `failed_operations` for manual cleanup). Checked at SHIP and LEARN stages; `in_sync: false` triggers a WARNING in the retrospective report. |
| `scout_improvements` | integer | Yes | Count of Boy Scout improvements made during implementation — small cleanup changes (unused imports, variable renames, helper extractions) applied opportunistically while modifying files. Tracked as `SCOUT-*` findings in the quality gate (no point deduction). Reported in the retrospective. |
| `conventions_hash` | string | Yes | SHA256 first 8 chars of full conventions_file content at PREFLIGHT. Agents should prefer `conventions_section_hashes` for granular drift detection. Empty if conventions file was unavailable. |
| `conventions_section_hashes` | object | Yes | Top-level per-section SHA256 hashes (first 8 chars) of conventions_file content at PREFLIGHT. Used for single-component projects. Keys are section names (e.g., `"architecture"`, `"naming"`, `"testing"`), values are hash strings. Enables granular drift detection — agents only react to changes in their relevant section. If conventions file was unavailable, set to `{}`. In multi-component projects, each component has its own `conventions_section_hashes` within `components[key]` — the top-level field is then set to `{}` and per-component hashes take precedence. |
| `detected_versions` | object | Yes | Project dependency versions detected at PREFLIGHT. `language`: detected language (e.g., "kotlin", "typescript"). `language_version`: language/compiler version. `framework`: primary framework (e.g., "spring-boot", "fastapi"). `framework_version`: framework version. `key_dependencies`: map of dependency name to version string for all detected libraries across all layers (language, framework, databases, messaging, persistence, testing). Values are `""` or `"unknown"` when detection fails — in that case, version-gated rules default to applying (conservative). Example: `{ "exposed-core": "0.48.0", "kafka-clients": "3.7.0", "flyway-core": "10.8.1", "caffeine": "3.1.8" }` |
| `check_engine_skipped` | integer | Yes | Count of inline check engine invocations that were skipped due to timeout or error during the current run. The `engine.sh` hook writes a counter to `.forge/.check-engine-skipped` on failure. The orchestrator copies this value to state.json at VERIFY Phase A entry, then deletes the marker file. Informational — VERIFY runs full checks regardless. |
| `lastCheckpoint` | string | No | ISO 8601 timestamp of the most recent skill invocation, written by the `forge-checkpoint.sh` PostToolUse hook. Updated after every Skill invocation. **Usage:** Read by PREFLIGHT during interrupted-run detection — a `lastCheckpoint` older than 24 hours combined with `complete: false` indicates a stale/abandoned run. Also read by the `.forge/.lock` stale timeout check (24h). Format: `"2026-03-30T12:00:00Z"`. |
| `mode` | string | Yes | Pipeline execution mode detected from requirement prefix or intent classification. Valid values: `"standard"` (default), `"migration"`, `"bootstrap"`, `"bugfix"`, `"testing"`, `"refactor"`, `"performance"`. Testing/refactor/performance modes use standard pipeline with behavioral modifications (reduced reviewers, refactor constraints, profiling focus). See orchestrator §3.0 for per-mode details. |
| `abort_reason` | string | No | Reason the pipeline was aborted. Set when the orchestrator auto-aborts. Values are prefix-matched strings (not fixed enums) — the orchestrator may append contextual details. Known prefixes: `"NO-GO timeout"` (validator returned NO-GO and user did not respond within timeout), `"budget exhausted"` (`total_retries >= total_retries_max`), `"recovery budget exhausted"` (`recovery_budget.total_weight >= max_weight`), `"user abort"` (user chose "Abort" at an escalation prompt), `"convergence regression"` (convergence engine detected REGRESSING state and user aborted), `"Bug unreproducible"` (bugfix mode — bug could not be reproduced after 3 attempts and user chose to close). Match using `startsWith()`, not exact equality. Empty string or absent when not aborted. Present only in terminal state (`complete: true`). |
| `recovery_failed` | boolean | No | Set to `true` by the recovery engine when recovery itself fails (e.g., state-reconstruction attempted but git unavailable). Triggers immediate escalation to user. Absent or `false` during normal operation. See `shared/recovery/recovery-engine.md` section 9. |
| `last_known_stage` | integer | No | Set by the recovery engine alongside `recovery_failed`. Records the last successfully entered stage (0-9) before recovery failure, enabling manual resume. Absent during normal operation. |
| `dry_run` | boolean | Yes | `true` when pipeline was invoked with `--dry-run` flag. Gates IMPLEMENT entry — if true, stages 4-9 are skipped and the pipeline outputs a dry-run report after VALIDATE. Default: `false`. |
| `autonomous` | boolean | No | `true` when pipeline runs in autonomous mode (resolved from `forge-config.md` at PREFLIGHT). When true, `AskUserQuestion` auto-selects recommended choices (logged `[AUTO]`), plan mode auto-approves after validator passes, but escalation events (E1-E4) still pause. Default: `false`. |
| `background` | boolean | No | `true` when the run is in background mode (activated via `--background` flag). Implies `autonomous: true`. Orchestrator suppresses interactive UI and writes progress artifacts to `.forge/progress/`. See `shared/background-execution.md`. Default: `false`. |
| `background_paused` | boolean | No | `true` when the background run is paused on an alert awaiting user resolution. Set alongside `background_alert_id`. Default: `false`. |
| `background_paused_at` | string\|null | No | ISO 8601 timestamp when the background pause began. `null` when not paused. |
| `background_alert_id` | string\|null | No | ID of the alert blocking progress (references `alerts.json`). `null` when not paused. |
| `abort_timestamp` | string | No | ISO 8601 timestamp of when abort was requested. Set alongside `abort_reason` by E9 transition. Absent when not aborted. |
| `shallow_clone` | boolean | No | `true` when the host repository is a shallow clone (detected via `git rev-parse --is-shallow-repository`). Set at PREFLIGHT by the worktree manager. When true, downstream agents should skip history-dependent analysis (`git log` depth, `git blame` hotspots, diff-based drift detection) and fall back to file-based analysis. Default: `false`. Absent or `false` for full clones. |
| `cross_repo` | object | No | Tracks cross-repo worktrees and status when `related_projects` is configured. Keys are project names; values contain `path`, `branch`, `status`, `files_changed`, and `pr_url`. See the [cross_repo section](#cross_repo-object-optional) above. Omitted when no cross-repo tasks exist. |
| `spec` | object\|null | No | Present when pipeline was invoked with `--spec <path>`. Contains `path`, `epic_title`, `story_count`, `has_technical_notes`, `has_nfr`, and `loaded_at`. `null` when not using spec-driven invocation. See the [spec section](#spec-object-optional) above. |
| `documentation` | object | Yes | Documentation subsystem state. Populated by `fg-130-docs-discoverer` at PREFLIGHT and updated by `fg-350-docs-generator` at DOCUMENTING. |
| `documentation.discovery_error` | boolean | Yes | `true` if `fg-130-docs-discoverer` timed out or failed during PREFLIGHT (documentation enabled but discovery failed). Default: `false`. When true, downstream agents (fg-350, fg-418-docs-consistency-reviewer) operate with degraded context — skip cross-referencing and coverage gap analysis. |
| `documentation.last_discovery_timestamp` | string | Yes | ISO8601 of last discovery run |
| `documentation.files_discovered` | number | Yes | Count of doc files found |
| `documentation.sections_parsed` | number | Yes | Count of parsed sections |
| `documentation.decisions_extracted` | number | Yes | Count of DocDecision entities |
| `documentation.constraints_extracted` | number | Yes | Count of DocConstraint entities |
| `documentation.code_linkages` | number | Yes | Count of DESCRIBES/DECIDES/CONSTRAINS relationships |
| `documentation.coverage_gaps` | array | Yes | Package paths with no doc coverage |
| `documentation.stale_sections` | number | Yes | Count of stale sections |
| `documentation.external_refs` | array | Yes | External doc URLs |
| `documentation.generation_history` | array | Yes | Array of generation run records. Each entry may include a `confidence_changes` array (see below). |
| `documentation.generation_history[].confidence_changes` | array | No | Array of confidence level changes made during this generation run. Each entry: `id` (decision/constraint ID), `from` (old level: `"LOW"`, `"MEDIUM"`, `"HIGH"`, or `null` for new items), `to` (new level: `"LOW"`, `"MEDIUM"`, `"HIGH"`, or `null` for dismissed items), `reason` (`"user_confirmed"`, `"user_dismissed"`, `"consistent_extraction_3_runs"`). |
| `documentation.generation_error` | boolean | Yes | `true` if `fg-350-docs-generator` timed out or failed during DOCUMENTING stage. Default: `false`. When true, the pipeline proceeds to SHIP without generated docs; the retrospective flags the failure. |
| `exploration_degraded` | boolean | Yes | `true` if all exploration agents timed out or failed during EXPLORE stage. Default: `false`. When true, the planner operates with reduced codebase context. |
| `confidence` | object | No | Confidence scoring data computed at PLAN completion. See `shared/confidence-scoring.md` for full algorithm. Absent before PLAN stage. |
| `confidence.overall` | number | — | Effective confidence score (0.0-1.0) after applying trust modifier. Computed as `raw_score * (0.5 + 0.5 * trust_level)`. |
| `confidence.clarity` | number | — | Requirement clarity dimension score (0.0-1.0). Regex-based assessment of word count, actors, entities, acceptance criteria. |
| `confidence.familiarity` | number | — | Pattern familiarity dimension score (0.0-1.0). Based on PREEMPT item matches, plan cache hits, and domain run history. |
| `confidence.complexity` | number | — | Codebase complexity dimension score (0.0-1.0, inverted -- higher means simpler). Based on affected file count, cross-component changes, cyclomatic complexity. |
| `confidence.history` | number | — | Historical success rate dimension score (0.0-1.0). Based on last 5 runs for the same `domain_area`. 0.3 when no prior runs exist. |
| `confidence.gate_decision` | string | — | Gate decision after confidence evaluation. Valid values: `"PROCEED"` (HIGH confidence), `"ASK"` (MEDIUM -- user confirmation requested), `"SUGGEST_SHAPE"` (LOW -- `/forge-shape` recommended). In autonomous mode, always logged but not enforced. |
| `eval` | object | No | Last eval run metadata. Informational only, not consumed by pipeline agents. Updated by `eval-runner.sh` after a live eval run completes (best-effort -- skipped if no `state.json` exists). |
| `eval.last_suite` | string | — | Name of the last eval suite that was run (e.g., `"lite"`, `"smoke"`). |
| `eval.last_run_timestamp` | string | — | ISO 8601 timestamp of the last eval run completion. |
| `eval.last_pass_rate` | number | — | Pass rate (0.0-1.0) from the last eval run. |
| `eval.last_result_file` | string | — | Relative path to the result JSON file from the last eval run (e.g., `"evals/pipeline/results/2026-04-14-10-30-00-lite.json"`). |

## `state.json` sub-object schemas

### tokens.by_stage entry schema

When populated by `forge-token-tracker.sh`, each stage entry has:

| Field | Type | Description |
|-------|------|-------------|
| `input` | integer | Input tokens consumed in this stage |
| `output` | integer | Output tokens generated in this stage |
| `agents` | string[] | Agent IDs dispatched in this stage |

### tokens.by_agent entry schema

| Field | Type | Description |
|-------|------|-------------|
| `input` | integer | Input tokens consumed by this agent |
| `output` | integer | Output tokens generated by this agent |
| `model` | string | Model used for this agent dispatch (`haiku`, `sonnet`, `opus`, or empty) |

### tokens.model_distribution

Object mapping model names to usage fractions. Example: `{ "haiku": 0.35, "sonnet": 0.45, "opus": 0.20 }`. Computed by `forge-token-tracker.sh` after each stage.

### tokens.model_fallbacks

Array of fallback events. Each entry: `{ "agent": "fg-200-planner", "requested": "opus", "actual": "sonnet", "reason": "model unavailable" }`.

### telemetry (object, optional)

OpenTelemetry GenAI semconv observability state. Spans are emitted in-process by `hooks/_py/otel.py` to a collector when `observability.otel.enabled=true`; authoritative recovery is `otel.replay()` over `.forge/events.jsonl`. See `shared/observability.md` for the durability contract and attribute table.

| Field | Type | Description |
|-------|------|-------------|
| `spans` | array | Append-only mirror of emitted spans (in-state audit only — not the source of truth). Attribute shape follows `shared/schemas/otel-genai-v1.json`. Capped at 500 entries per run. |

**Lifecycle:**
- Initialized at PREFLIGHT with `{ "spans": [] }`
- Spans mirrored by `hooks/_py/otel.py` at close time
- Reset at PREFLIGHT for each new run

Removed in forge 3.4.0: `telemetry.metrics` aggregation, `telemetry.export_status`. Metrics are derived from span attributes at the collector; export status is implicit (live stream best-effort, replay authoritative).

### Tracking Fields

| Field | Type | Description |
|-------|------|-------------|
| `ticket_id` | string or null | Kanban ticket ID (e.g., `FG-001`). Null if tracking not initialized. Set at PREFLIGHT. |
| `branch_name` | string | Full branch name (e.g., `feat/FG-001-user-notifications`). Set at PREFLIGHT when worktree is created. |
| `tracking_dir` | string or null | Path to tracking directory (e.g., `.forge/tracking`). Null if tracking not initialized. |

These fields are set during PREFLIGHT (Stage 0) when the worktree is created (see `fg-100-orchestrator.md`). They remain constant for the duration of the run.

### Bugfix Fields

Present when `mode == "bugfix"`. Null/empty defaults for other modes.

| Field | Type | Description |
|-------|------|-------------|
| `bugfix.source` | enum or null | `"kanban"`, `"linear"`, `"description"`. How the bug was reported. |
| `bugfix.source_id` | string or null | Ticket/issue ID. Null for descriptions before ticket creation. |
| `bugfix.reproduction.method` | enum or null | `"automated"`, `"manual"`, `"unresolvable"`. Set at Stage 2. |
| `bugfix.reproduction.test_file` | string or null | Path to reproduction test file (if automated). |
| `bugfix.reproduction.attempts` | integer | Reproduction attempts count (max 3). Default: 0. |
| `bugfix.context_retries` | integer | "Provide more context" re-run count. Max 2 — option removed after reaching limit. Default: 0. |
| `bugfix.root_cause.hypothesis` | string or null | Description of confirmed/suspected root cause. |
| `bugfix.root_cause.category` | enum or null | `"off_by_one"`, `"null_handling"`, `"race_condition"`, `"missing_validation"`, `"wrong_assumption"`, `"config_error"`. |
| `bugfix.root_cause.affected_files` | array | File paths affected by the bug. Default: []. |
| `bugfix.root_cause.confidence` | enum or null | `"high"`, `"medium"`, `"low"`. |

### cross_repo (object, optional)

Tracks worktrees and status for changes in related projects. Only populated when `related_projects` is configured and cross-repo tasks exist.

```json
{
  "cross_repo": {
    "{project_name}": {
      "path": "string — absolute path to worktree in related project",
      "branch": "string — branch name created for cross-repo changes",
      "status": "string — implementing | complete | failed",
      "files_changed": ["string — list of files modified"],
      "pr_url": "string | null — PR URL if created"
    }
  }
}
```

**Lifecycle:**
- Created when orchestrator creates a cross-repo worktree during IMPLEMENT
- Updated to `complete` when cross-repo implementation succeeds
- Updated to `failed` on errors
- `pr_url` populated during SHIP if PR creation succeeds
- Cleaned up by `/forge-recover rollback` or `/forge-recover reset`

---

### spec (object, optional)

Present when pipeline was invoked with `--spec <path>`. Stores parsed spec metadata.

```json
{
  "spec": {
    "path": "string — path to the spec file",
    "epic_title": "string — extracted epic title",
    "story_count": "number — count of stories in spec",
    "has_technical_notes": "boolean — true if ## Technical Notes section present",
    "has_nfr": "boolean — true if ## Non-Functional Requirements section present",
    "loaded_at": "string — ISO 8601 timestamp"
  }
}
```

---

### ai_quality_tracking (object, optional)

Tracks AI-specific finding patterns across pipeline runs. Created by `fg-700-retrospective` on first detection of `AI-*` findings. Persists across runs (not reset by `/forge-recover reset`).

```json
{
  "ai_quality_tracking": {
    "run_counts": {
      "AI-LOGIC-ASYNC": 4,
      "AI-PERF-N-PLUS-ONE": 2
    },
    "promoted_preempts": [
      "SCOUT-AI-LOGIC-ASYNC"
    ],
    "last_updated": "2026-04-14T10:30:00Z"
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `run_counts` | `object<string, number>` | Count of runs where each `AI-*` category was detected |
| `promoted_preempts` | `string[]` | SCOUT-AI categories that have been promoted to PREEMPT items |
| `last_updated` | `string (ISO 8601)` | Timestamp of last update |

---

### graph (object, optional)

Tracks graph update state for incremental updates at stage boundaries.

| Field | Type | Description |
|-------|------|-------------|
| `last_update_stage` | integer | Stage number (0-9) when graph was last updated |
| `last_update_files` | string[] | Files re-indexed in the last update |
| `stale` | boolean | True when files changed since last graph update |

**Lifecycle:**
- Created at PREFLIGHT (Stage 0) when `graph.enabled` is true
- Updated at post-IMPLEMENT, post-VERIFY, pre-REVIEW by the orchestrator
- `stale` set to `true` by orchestrator when `files_changed` grows; reset to `false` after each successful update
- Reviewers querying the graph check `stale` — if `true`, log INFO but proceed

---

### evidence (object, optional)

Tracks pre-ship verification attempts and results. Created by `fg-590-pre-ship-verifier`, read by `fg-100-orchestrator` and `fg-600-pr-builder`.

```json
{
  "evidence": {
    "last_run": "2026-04-05T14:32:00Z",
    "verdict": "SHIP",
    "attempts": 2,
    "block_history": [
      {
        "attempt": 1,
        "reasons": ["tests.failed: 3"],
        "timestamp": "2026-04-05T14:20:00Z"
      }
    ]
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `last_run` | string (ISO 8601) | When fg-590 last ran |
| `verdict` | string | Last verdict: `"SHIP"` or `"BLOCK"` |
| `attempts` | integer | How many times fg-590 was dispatched this run |
| `block_history` | array | Append-only log of BLOCK verdicts with reasons and timestamps. Capped at 20 entries (FIFO). |

**Lifecycle:**
- Created when fg-590 first runs (after Stage 7)
- Updated on each fg-590 invocation
- `attempts` incremented each time; `block_history` appended on BLOCK
- The full evidence artifact lives at `.forge/evidence.json` (see `shared/verification-evidence.md`); `state.json.evidence` is the summary for state tracking and retrospective analysis
- Reset at PREFLIGHT for each new run

---

### `decomposition` (object, optional)

Present when auto-decomposition was triggered (via fast scan or deep scan). Null/absent otherwise.

```json
{
  "decomposition": {
    "source": "fast_scan | deep_scan",
    "original_requirement": "string",
    "extracted_features": [
      {
        "id": "feat-1",
        "title": "string",
        "description": "string",
        "scope": "S | M | L",
        "domain": "string",
        "depends_on": ["feat-2"]
      }
    ],
    "routing": "parallel | serial | single",
    "user_selection": ["feat-1", "feat-3"],
    "classified_intent": "bugfix | migration | bootstrap | multi-feature | vague | standard",
    "classification_signals": ["signal1", "signal2"]
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `source` | string | How decomposition was triggered: `fast_scan` (pre-explore) or `deep_scan` (post-explore) |
| `original_requirement` | string | Original requirement text before decomposition |
| `extracted_features` | array | Extracted features with id, title, description, scope, domain, dependencies |
| `routing` | string | Execution mode: `parallel`, `serial`, or `single` (cherry-picked) |
| `user_selection` | array | Feature IDs selected for execution (may be subset) |
| `classified_intent` | string | Intent classification result from forge-run |
| `classification_signals` | array | Signals that triggered the classification |

---

### Per-Run State (Sprint Mode)

In sprint mode, each feature gets its own state directory:

```
.forge/runs/{feature-id}/
  state.json              # Same schema as root state.json
  checkpoint-*.json       # Same as root
  stage_N_notes_*.md      # Same as root
  .lock                   # Per-run lock
```

The root `.forge/state.json` is NOT used in sprint mode. Each `runs/{feature-id}/state.json` is a complete, independent pipeline state.

Sprint-level state is tracked in `.forge/sprint-state.json` (see `shared/sprint-state-schema.md`).

---

### components (object, required)

Per-component state tracking for monorepo and multi-stack projects. Single-repo projects have one component.

```json
{
  "components": {
    "backend": {
      "story_state": "IMPLEMENTING",
      "conventions_hash": "ab12cd34",
      "conventions_section_hashes": {},
      "detected_versions": {
        "language_version": "2.0.0",
        "framework_version": "3.3.0"
      },
      "score_history": [85, 92, 95]
    },
    "frontend": {
      "story_state": "EXPLORING",
      "conventions_hash": "ef56gh78",
      "conventions_section_hashes": {},
      "detected_versions": {
        "language_version": "5.4.0",
        "framework_version": "18.2.0"
      },
      "score_history": []
    }
  }
}
```

Extended example showing `path` and `convention_stack`:

```json
"components": {
  "backend": {
    "path": "services/user-service",
    "convention_stack": [
      "modules/languages/kotlin.md",
      "modules/frameworks/spring/conventions.md",
      "modules/frameworks/spring/variants/kotlin.md",
      "modules/databases/postgresql.md",
      "modules/frameworks/spring/databases/postgresql.md",
      "modules/persistence/exposed.md",
      "modules/frameworks/spring/persistence/exposed.md",
      "modules/messaging/kafka.md",
      "modules/frameworks/spring/messaging/kafka.md",
      "modules/testing/kotest.md",
      "modules/frameworks/spring/testing/kotest.md"
    ],
    "story_state": "PREFLIGHT",
    "conventions_hash": "",
    "conventions_section_hashes": {},
    "detected_versions": {
      "language_version": "2.1.0",
      "framework_version": "3.4.1"
    }
  }
}
```

**Fields per component:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `story_state` | string | Yes | Pipeline state for this component. Same valid values as top-level `story_state`. Independent per component — frontend can be EXPLORING while backend is IMPLEMENTING. |
| `conventions_hash` | string | Yes | SHA-256 hash of the resolved convention stack for this component. Updated at PREFLIGHT. Used for mid-run convention drift detection. |
| `conventions_section_hashes` | object | Yes | Per-section hashes within the convention stack. Keys are section names, values are SHA-256 hashes. Enables agents to react only to changes in their relevant sections. |
| `detected_versions` | object | Yes | Runtime-detected versions for this component. Fields: `language_version` (string), `framework_version` (string), `key_dependencies` (object, dependency_name → version_string). Populated at PREFLIGHT from manifests (package.json, build.gradle.kts, Cargo.toml, etc.). |
| `score_history` | integer[] | No | Per-component quality scores from review cycles. Only present after the component has been through REVIEW. The top-level `score_history` contains the aggregate scores. |
| `convergence` | object | No | Per-component convergence state (same schema as top-level `convergence`). Only present for multi-component projects where components iterate independently. |
| `convention_stack` | string[] | No | Array of resolved convention file paths in composition order. Populated by PREFLIGHT. Empty array if not yet resolved. |
| `path` | string | No | Relative path prefix for this component. Used by the check engine for per-file convention routing. Required in multi-service mode. Defaults to project root in single-service mode. |

**Component key derivation:** For single-component projects, the key comes from the `forge.local.md` config (e.g., `"backend"`). For multi-component projects with `components:` block and `path:` fields, keys are the component names from config. Components without a `path:` field use the component name as both key and path prefix.

**Initialization:** Components are initialized at PREFLIGHT with `story_state: "PREFLIGHT"`, empty hashes, and detected versions from manifest scanning. If version detection fails for a component, `detected_versions` is set to `{ "language_version": "unknown", "framework_version": "unknown" }` and a WARNING is logged.

---

### active_component (string, required)

The component the orchestrator is currently processing. Set before dispatching agents for a component's tasks. Used by the check engine to route rules.

Example: `"active_component": "backend"`

---

### Required Fields

The following fields are required in every state.json (all schema versions):

`version`, `complete`, `story_id`, `story_state`, `components`, `active_component`, `total_retries`, `total_retries_max`, `branch_name`

All other fields in the Field Reference table marked "Yes" are also required; the list above is the minimum set the recovery engine validates on load.

---

### Migration State (stored in `state.json.migration` during migration runs)

During migration mode (triggered by `/forge-migration` or `/forge-run "migrate: ..."`), the `migration` object is added to `state.json` by `fg-160-migration-planner`. This object tracks the full lifecycle of a migration run, including version detection, impact analysis, and per-phase progress.

| Field | Type | Description |
|-------|------|-------------|
| `migration_id` | string | Unique identifier for this migration run |
| `current_version` | string | Detected or specified current version of the library being migrated |
| `target_version` | string | Target version (auto-detected latest stable or user-specified) |
| `migration_path` | string[] | Ordered list of intermediate versions if stepping through majors (e.g., `["3.3.0", "3.4.1"]`) |
| `impact_analysis` | object | Breaking changes, new requirements, deprecated APIs in target (from DETECT phase) |
| `impact_analysis.breaking_changes` | array | List of `{ "category": "<type>", "description": "...", "affected_pattern": "...", "replacement": "...", "source": "..." }` |
| `impact_analysis.new_requirements` | string[] | Runtime/toolchain requirements introduced by the target version |
| `impact_analysis.deprecated_apis_in_target` | array | APIs deprecated in target: `{ "pattern": "...", "replacement": "...", "severity": "WARNING" }` |
| `impact_analysis.risk_level` | string | Overall risk assessment: `"LOW"`, `"MEDIUM"`, `"HIGH"` |
| `current_phase` | integer | Current migration phase number (0 = DETECT, 1 = AUDIT, 2 = PREPARE, 3+ = MIGRATE, N+1 = CLEANUP, N+2 = VERIFY) |
| `phase_name` | string | Current phase name (e.g., `"DETECT"`, `"AUDIT"`, `"PREPARE"`, `"MIGRATE:billing"`, `"CLEANUP"`, `"VERIFY"`) |
| `total_phases` | integer | Total number of planned migration phases |
| `batch_in_phase` | integer | Current batch number within the active phase |
| `files_migrated` | integer | Count of successfully migrated files |
| `files_skipped` | integer | Count of files skipped (rollback or dependency issues) |
| `files_manual` | integer | Count of files flagged for manual intervention |
| `files_remaining` | integer | Count of files not yet processed |
| `rollbacks` | integer | Count of batch rollbacks across the entire migration run |
| `last_commit_sha` | string | SHA of the most recent migration commit |

Example:

```json
{
  "story_state": "MIGRATING",
  "migration": {
    "migration_id": "migrate-spring-boot-3.2-to-3.4",
    "current_version": "3.2.4",
    "target_version": "3.4.1",
    "migration_path": ["3.3.0", "3.4.1"],
    "impact_analysis": {
      "risk_level": "MEDIUM",
      "breaking_changes": [
        {
          "category": "API_REMOVED",
          "description": "RestTemplate default timeout changed",
          "affected_pattern": "new RestTemplate()",
          "replacement": "RestTemplate with explicit timeout config",
          "source": "https://spring.io/blog/2024/..."
        }
      ],
      "new_requirements": ["Java 17+ required (was Java 11+)"],
      "deprecated_apis_in_target": [
        { "pattern": "WebSecurityConfigurerAdapter", "replacement": "SecurityFilterChain bean", "severity": "WARNING" }
      ]
    },
    "current_phase": 3,
    "phase_name": "MIGRATE:billing",
    "total_phases": 6,
    "batch_in_phase": 2,
    "files_migrated": 42,
    "files_skipped": 2,
    "files_manual": 1,
    "files_remaining": 15,
    "rollbacks": 1,
    "last_commit_sha": "abc123"
  }
}
```

## security.injection_* (added in 3.1.0)

Counters incremented by `hooks/_py/mcp_response_filter.py` (via orchestrator callback) for `events_count` and `blocks_count`; incremented by the orchestrator confirmation gate for `confirmations_requested`. Read by `fg-700-retrospective` and `/forge-insights`. All fields are optional and default to 0 / null.

```json
{
  "security": {
    "injection_events_count": 0,
    "injection_blocks_count": 0,
    "injection_confirmations_requested": 0,
    "last_event_ts": null
  }
}
```

| Field | Type | Description |
|---|---|---|
| `security.injection_events_count` | integer | Total invocations of the MCP response filter for this run, regardless of outcome. |
| `security.injection_blocks_count` | integer | Subset of `injection_events_count` that resulted in a `quarantine` action (BLOCK-tier match). |
| `security.injection_confirmations_requested` | integer | T-C-tier ingresses to a `Bash`-capable agent that fired the `AskUserQuestion` confirmation gate (see `shared/ask-user-question-patterns.md`). |
| `security.last_event_ts` | string \| null | RFC 3339 UTC timestamp of the most recent filter invocation, or `null` if none. |

## events.jsonl

Unified append-only event log capturing all pipeline events. See `shared/event-log.md` for full documentation, event types, and causal chain structure. See `shared/schemas/event-schema.json` for the JSON Schema.

### Location

- Standard mode: `.forge/events.jsonl`
- Sprint mode: `.forge/runs/{id}/events.jsonl` (per-run isolation)

### Lifecycle

- Created on first event emission (typically `PIPELINE_START` at PREFLIGHT).
- Appended by `shared/emit-event.sh` throughout the pipeline run.
- **Survives `/forge-recover reset`** -- only manual `rm -rf .forge/` removes it.
- Events older than `events.retention_days` (default: 90) pruned at PREFLIGHT.
- File size pruned when exceeding `events.max_file_size_mb` (default: 50).

### Configuration

Configured in `forge-config.md` under the `events:` section:

| Parameter | Type | Default | Range | Description |
|-----------|------|---------|-------|-------------|
| `events.enabled` | boolean | `true` | — | Master toggle. When false, no events are written. |
| `events.retention_days` | integer | `90` | 1-365 | Events older than this are pruned at PREFLIGHT. |
| `events.max_file_size_mb` | integer | `50` | 10-200 | Prune oldest events when file exceeds this size. |
| `events.replay_enabled` | boolean | `true` | — | Enable `/forge-replay` skill. |
| `events.emit_state_writes` | boolean | `true` | — | Emit STATE_WRITE events (can be verbose). |
| `events.backward_compat` | boolean | `true` | — | Also write to `decisions.jsonl` and `progress/timeline.jsonl`. |

### Backward Compatibility

When `events.backward_compat: true` (default), DECISION events are also written to `.forge/decisions.jsonl` and all events in background mode are also written to `.forge/progress/timeline.jsonl`. This maintains compatibility with existing consumers during the migration period.

## Version Migration

This section documents the evolution of the `state.json` schema and the protocol the orchestrator uses to detect and upgrade old state files.

### Migration History

| From | To | Summary | Fields Added | Default Values |
|------|----|---------|-------------|----------------|
| — | 1.0.0 | Initial schema | `stage`, `story_state`, `score_history`, `findings`, `complete`, `story_id`, `requirement`, `domain_area`, `risk_level`, `active_component`, `components`, `quality_cycles`, `test_cycles`, `verify_fix_count`, `validation_retries`, `total_retries`, `total_retries_max`, `score_history`, `convergence`, `integrations`, `linear`, `linear_sync`, `modules`, `cost` | See schema above |
| 1.0.0 | 1.1.0 | Added tracking fields and recovery section | `ticket_id`, `branch_name`, `tracking_dir`, `recovery`, `total_retries`, `mode` | `null`, `""`, `null`, `{}`, `0`, `"standard"` |
| 1.1.0 | 1.2.0 | Added convergence counters, phase tracking, and graph section | `graph`, `convergence.phase_history`, `convergence.safety_gate_passed`, `convergence.safety_gate_failures` | `{ "last_update_stage": -1, "last_update_files": [], "stale": false }`, `[]`, `false`, `0` |
| 1.2.0 | 1.3.0 | Added decomposition section, explore-cache fields, visual companion | `decomposition`, `explore_cache_hit`, `plan_cache_hit`, `visual_companion` | `null`, `false`, `false`, `false` |
| 1.3.0 | 1.4.0 | Added telemetry/tokens section, evidence tracking, sprint support, cost breakdown | `tokens`, `evidence`, `feedback_loop_count`, `detected_versions`, `cost.estimated_cost_usd`, `recovery_budget`, `decision_quality` | `{}`, `{ "last_run": null, "verdict": null, "attempts": 0, "block_history": [] }`, `0`, `{}`, `0.0`, `{ "total_weight": 0.0, "max_weight": 5.5, "applications": [] }`, `{}` |
| 1.4.0 | 1.5.0 | Added convention drift tracking, WAL versioning, preempt status | `_seq`, `previous_state`, `convergence.diminishing_count`, `convergence.unfixable_info_count`, `preempt_items_status`, `conventions_section_hashes` | `1`, `""`, `0`, `0`, `{}`, `{}` |
| 1.5.0 | 1.6.0 | (v2.7.0) Added circuit breaker tracking, planning critic counter, schema migration history | `recovery.circuit_breakers`, `critic_revisions`, `schema_version_history` | `{}`, `0`, `[]` |
| 1.6.0 | 1.7.0 | (v2.0) Added confidence scoring, adaptive trust, context condensation, knowledge references | `confidence`, `convergence.condensation`, `tokens.condensation_savings`, `tokens.condensation_count`, `tokens.condensation_cost`, `tokens.effective_token_ratio` | `null` (computed at PLAN), see condensation defaults above, `0`, `0`, `0`, `1.0` |
| 1.7.0 | 1.8.0 | (v2.0) Added output compression tracking | `tokens.compression_level_distribution`, `tokens.output_tokens_per_agent` | `{ "verbose": 0, "standard": 0, "terse": 0, "minimal": 0 }`, `{}` |
| 1.8.0 | 1.9.0 | (Forge 3.1.0) Self-consistency voting counters + time-travel CAS checkpoints. Breaking: CAS DAG replaces linear `.forge/checkpoint-*.json`; `/forge-recover reset` required for pre-1.9.0 state. | `consistency_cache_hits`, `consistency_votes`, `checkpoints`, `head_checkpoint` | `0`, `{ "shaper_intent": { "invocations": 0, "cache_hits": 0, "low_consensus": 0 }, "validator_verdict": { "invocations": 0, "cache_hits": 0, "low_consensus": 0 }, "pr_rejection_classification": { "invocations": 0, "cache_hits": 0, "low_consensus": 0 } }`, `[]`, `""` |
| 1.9.0 | 1.10.0 | (Forge 3.6.0) Session handoff tracking sub-object for preserving run state across Claude Code session boundaries. | `handoff.last_written_at`, `handoff.last_path`, `handoff.chain`, `handoff.soft_triggers_this_run`, `handoff.hard_triggers_this_run`, `handoff.milestone_triggers_this_run`, `handoff.suppressed_by_rate_limit` | `null`, `null`, `[]`, `0`, `0`, `0`, `0` |

### Version Detection and Upgrade Protocol

The orchestrator detects the state version at PREFLIGHT (Stage 0) and applies migrations:

1. **Read** `state.json`. If the file does not exist, create a fresh state with the current schema version. Proceed normally.
2. **Check** `state.json.version` field.
3. **Missing version:** State file is treated as corrupted -- reinitialized from PREFLIGHT defaults. Log ERROR "Corrupted state.json (missing version), starting fresh."
4. **Matching version** (equals current plugin schema version): Proceed normally.
5. **Older version:** Apply migrations sequentially (e.g., 1.0.0 -> 1.1.0 -> 1.2.0 -> ... -> current). Each migration adds missing fields with safe defaults. Existing fields are never overwritten. After all migrations, update `version` to the current schema version and write via `forge-state-write.sh`.
6. **Newer version** (state was written by a newer plugin version): Log WARNING "State version {v} is newer than plugin version {current}. Proceeding with best-effort compatibility." Do not downgrade. Unknown fields are preserved but ignored.
7. **Corrupt JSON:** If `state.json` contains invalid JSON, create a fresh state and log ERROR "Corrupted state.json (invalid JSON), starting fresh."

### Migration Safety

- Migrations are **additive only**: new fields with safe defaults. No field removals or renames between versions.
- Missing fields are populated with defaults; existing fields are never overwritten by migration.
- Migration is logged to `.forge/.hook-failures.jsonl` with reason `state_migration:{from}->{to}` (one JSON row per migration event).
- The recovery engine checks the version field before parsing -- version mismatch triggers migration before any other state processing.

**Manual reset:** Use `/forge-recover reset` to clear stale state if automatic migration is insufficient.

### story_state Valid Values

| Value | Stage | Description |
|-------|-------|-------------|
| `"PREFLIGHT"` | 0 | Config loading, state initialization, interrupted-run check |
| `"EXPLORING"` | 1 | Codebase exploration agents running |
| `"PLANNING"` | 2 | Planner decomposing requirement into stories and tasks |
| `"VALIDATING"` | 3 | Validator reviewing plan from 7 perspectives |
| `"IMPLEMENTING"` | 4 | Scaffolder and implementer writing code per task |
| `"VERIFYING"` | 5 | Build, lint, and test verification |
| `"REVIEWING"` | 6 | Quality gate agents reviewing code |
| `"DOCUMENTING"` | 7 | Documentation updates (CLAUDE.md, KDoc/TSDoc) |
| `"SHIPPING"` | 8 | Branch creation, commit, PR |
| `"LEARNING"` | 9 | Retrospective analysis, config tuning, report generation |
| `"MIGRATING"` | - | Migration planner executing (DETECT/AUDIT/PREPARE/MIGRATE phases) |
| `"MIGRATION_PAUSED"` | - | Migration paused due to rollback threshold or user intervention |
| `"MIGRATION_CLEANUP"` | - | Removing old dependencies and shims |
| `"MIGRATION_VERIFY"` | - | Post-migration verification (tests + compatibility checks) |
| `"DECOMPOSED"` | - | Requirement decomposed into multiple features; sprint orchestrator taking over |

Migration states are used exclusively by `fg-160-migration-planner` during `/forge-migration` runs. They are not part of the standard pipeline flow.

**Multi-module only states** (used in `modules[].story_state`, never at top level):

| Value | Description |
|-------|-------------|
| `"FAILED"` | Terminal — module failed after max retries. Pipeline continues with remaining modules. |
| `"BLOCKED"` | Module waiting on a dependency module. Includes `blocked_by` field. Automatically transitions when dependency completes. |

### story_state Transitions

The normal flow is linear: `PREFLIGHT -> EXPLORING -> PLANNING -> VALIDATING -> IMPLEMENTING -> VERIFYING -> REVIEWING -> DOCUMENTING -> SHIPPING -> LEARNING`.

Valid retry loops:
- `VALIDATING -> PLANNING` (REVISE verdict, up to `validation.max_validation_retries`)
- `VERIFYING -> IMPLEMENTING` (test failures dispatched to implementer, up to `test_gate.max_test_cycles`)
- `REVIEWING -> IMPLEMENTING` (quality fix cycle, up to `quality_gate.max_review_cycles`)
- `SHIPPING -> IMPLEMENTING` (user rejects PR with implementation-level feedback, resets quality and test counters)
- `SHIPPING -> PLANNING` (user rejects PR with design-level feedback, resets stage-specific counters but NOT `total_retries`)

All retry loops also increment `total_retries`. When `total_retries >= total_retries_max`, the orchestrator escalates regardless of individual loop budgets.

---

## checkpoint-{storyId}.json

> **DEPRECATED in v1.9.0.** This linear per-story file format is replaced by the content-addressable DAG documented in §Checkpoints above. New runs write to `.forge/runs/<run_id>/checkpoints/` via `hooks/_py/time_travel`. The schema below is retained for reference only — orchestrators on v1.9.0+ never read or write these files, and `/forge-recover reset` is required to migrate pre-1.9.0 state.

Per-story recovery checkpoint. Created and updated during Stage 4 (IMPLEMENT) after each task completes. Enables resuming implementation at the exact task where a conversation was interrupted.

### Schema

```json
{
  "storyId": "feat-plan-comments",
  "stage": 4,
  "current_group": 2,
  "tasks_completed": [
    {
      "taskId": "T001",
      "status": "pass",
      "files_created": ["core/domain/plan/PlanComment.kt"],
      "files_modified": [],
      "fix_attempts": 0,
      "preempt_items_used": ["check-openapi-before-controller"]
    },
    {
      "taskId": "T002",
      "status": "pass",
      "files_created": [],
      "files_modified": ["core/impl/plan/ICreatePlanCommentUseCaseImpl.kt"],
      "fix_attempts": 1,
      "preempt_items_used": []
    }
  ],
  "tasks_remaining": ["T003", "T004"],
  "last_action": "fg-300-implementer completed T002",
  "timestamp": "2026-03-21T10:15:00Z"
}
```

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `storyId` | string | Yes | Story identifier matching `state.json.story_id`. Used to correlate checkpoint with the run. |
| `stage` | integer | Yes | Pipeline stage number (0-9) at which this checkpoint was written. Typically `4` (IMPLEMENT), but may be updated during VERIFY/REVIEW retry loops. During targeted re-implementation (Stage 5→4 or Stage 6→4), the stage field is set to `4` while the targeted fix runs, then reverts to the originating stage (5 or 6) when control returns. The `story_state` in `state.json` tracks the logical stage, while the checkpoint `stage` tracks where the last physical task completion occurred. |
| `current_group` | integer | Yes | The parallel group currently being executed (1-indexed). Groups are sequential; tasks within a group may be parallel. Valid range: 1 to max 3 (plan defines up to 3 parallel groups). |
| `tasks_completed` | array | Yes | List of completed task objects. Each object contains the fields described below. Ordered by completion time. |
| `tasks_completed[].taskId` | string | Yes | Task identifier from the plan (e.g., `"T001"`, `"T002"`). |
| `tasks_completed[].status` | string | Yes | Task outcome. Valid values: `"pass"` (task completed successfully), `"fail"` (task failed after max fix attempts), `"skipped"` (task skipped due to dependency failure). |
| `tasks_completed[].files_created` | string[] | Yes | Relative paths of files created by this task. Empty array if no new files. |
| `tasks_completed[].files_modified` | string[] | Yes | Relative paths of files modified by this task (excluding files listed in `files_created`). Empty array if no modifications. |
| `tasks_completed[].fix_attempts` | integer | Yes | Number of fix attempts for this task (0 = succeeded on first try). Max is `implementation.max_fix_loops` from config. |
| `tasks_completed[].preempt_items_used` | string[] | Yes | PREEMPT item identifiers that were applied during this task. Empty array if none. Used by the orchestrator to populate `state.json.preempt_items_status`. |
| `tasks_remaining` | string[] | Yes | Task IDs not yet started. Shrinks as tasks complete. Empty array when all tasks are done. |
| `last_action` | string | Yes | Human-readable description of the most recent action taken. Used for logging and recovery context. Examples: `"fg-310-scaffolder generated T003 boilerplate"`, `"fg-300-implementer completed T002"`, `"build fix attempt 2 for T004"`. |
| `timestamp` | string | Yes | ISO 8601 timestamp of when this checkpoint was last written. Used to determine freshness during recovery. |

### Recovery Behavior

When PREFLIGHT detects an interrupted run (`.forge/state.json` exists with `complete: false`):

1. Read `state.json` to find `story_state` and `last_commit_sha`.
2. If `story_state` is `"IMPLEMENTING"`: read `checkpoint-{storyId}.json` to find exactly which tasks are done.
3. Run `git diff {last_commit_sha}` to detect filesystem drift since the checkpoint.
4. If drift detected: warn user, ask whether to incorporate changes or discard.
5. Resume from the first incomplete task in the current group.
6. If `--from` flag is provided: it overrides checkpoint recovery and jumps to the specified stage.

---

## Stage Notes Files

### stage_N_notes_{storyId}.md

Free-form markdown written by each stage's agent(s). Contains decisions, findings, exploration results, or review reports relevant to that stage.

- `N` is the stage number (0-9).
- Created at stage entry, may be appended during the stage.
- Read by the retrospective agent at Stage 9 for analysis.

### stage_final_notes_{storyId}.md

Written by the retrospective agent at Stage 9. Contains the run summary, extracted learnings, and tuning recommendations. This is the primary input for `forge-log.md` updates.

---

## Feedback Directory

### feedback/{date}-{topic}.md

Individual feedback files created by `fg-710-post-run` (Part A: Feedback Capture) when the user corrects the pipeline's approach. Format:

```markdown
# Feedback: {topic}
Date: {YYYY-MM-DD}
Stage: {stage where correction occurred}
Context: {what the pipeline did wrong}
Correction: {what the user wanted instead}
Category: {PREEMPT | PATTERN | CONVENTION | PREFERENCE}
Applied: false
```

### feedback/summary.md

Created by the retrospective agent when the feedback directory contains more than 20 individual files. Consolidates patterns from individual feedback into actionable rules. Individual files that have been incorporated are moved to `feedback/archive/`.

### feedback/archive/

Contains individual feedback files that have been consolidated into `summary.md` or applied as PREEMPT items in `forge-log.md`. Preserved for audit trail.

---

## Reports Directory

### reports/forge-{YYYY-MM-DD}.md

Per-run retrospective report written by `fg-700-retrospective` at Stage 9. Contains:

- Run metadata (story_id, requirement, duration, risk_level)
- Stage-by-stage timing breakdown
- Quality gate results (score history, final verdict, finding summary)
- Test gate results (pass/fail, cycles needed, coverage delta)
- Fix loop statistics (verify_fix_count, quality_cycles, test_cycles)
- Extracted learnings (PREEMPT, PATTERN, TUNING)
- Auto-tuning actions taken
- Comparison against previous runs (trend data)

If multiple runs occur on the same date, reports use a suffix: `forge-{YYYY-MM-DD}-2.md`, `forge-{YYYY-MM-DD}-3.md`.

### reports/recap-{YYYY-MM-DD}-{storyId}.md

Human-readable run recap written by `fg-710-post-run` (Part B: Recap) at Stage 9, after the retrospective. Contains:

- What was built (per-story summary with file lists)
- Key decisions made (with trade-off reasoning)
- Boy Scout improvements (SCOUT-* findings)
- Unfixed findings (with explanation and follow-up tickets)
- Pipeline metrics (files, tests, fix cycles, score progression)
- Learnings captured (PREEMPT items added/updated)

If Linear is available, a summarized version (max 2,000 chars) is posted as a comment on the Epic. If a PR exists, the "What Was Built" and "Key Decisions" sections are appended to the PR description.

---

## Orchestrator Input Payload

When `fg-100-orchestrator` is dispatched as a subagent (by a `/forge-*` skill or nested invocation), the skill passes an input payload describing the requested operation. The orchestrator parses this payload at entry and routes accordingly.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `recovery_op` | string | no | One of `diagnose`, `repair`, `reset`, `resume`, `rollback`, `rewind`, `list-checkpoints`. Present when `fg-100-orchestrator` is dispatched from `/forge-recover`. Absent otherwise; orchestrator proceeds with normal pipeline. `rewind` and `list-checkpoints` added in v1.9.0. |

---

## § Checkpoints

**Breaking change in v1.9.0:** the legacy `.forge/checkpoint-{storyId}.json` linear file layout is **removed**. Checkpoints now live under `.forge/runs/<run_id>/checkpoints/` in a content-addressable DAG:

```
.forge/runs/<run_id>/checkpoints/
├── by-hash/<aa>/<sha256-tail>/
│   ├── manifest.json            # {state_hash, worktree_sha, events_hash, memory_hash, parent_ids[], compression}
│   ├── state.json               # canonical JSON snapshot
│   ├── events.slice.jsonl       # events since parent
│   └── memory.tar.<gz|zst>      # stage_notes + PREEMPT + forge-log excerpt
├── index.json                   # {"<human-id>": "<sha256>", ...}
├── tree.json                    # {"<sha>": {parents, children, created_at, stage, task, human_id}}
└── HEAD                         # active checkpoint sha
```

See `shared/recovery/time-travel.md` for the full protocol, atomic restore semantics, and GC policy.

### state.json additions

```json
{
  "checkpoints": [
    {
      "id": "IMPLEMENT.T1.004",
      "hash": "a3f9c1...",
      "stage": "IMPLEMENTING",
      "task": "T1",
      "created_at": "2026-04-19T10:14:22Z",
      "parents": ["a1b2f0..."]
    }
  ],
  "head_checkpoint": "a3f9c1..."
}
```

- `checkpoints` is append-only within a run. Pre-rewind entries are retained for audit.
- `head_checkpoint` mirrors `.forge/runs/<run_id>/checkpoints/HEAD`.

### Refusal behavior

Orchestrator at startup reads `state.json.version`. If < `1.9.0`, refuses to proceed with error:
`state.json v<detected> detected; v1.9.0 required. Run /forge-recover reset to start fresh.`

No automatic migration — the checkpoint format is incompatible. Legacy `.forge/checkpoint-*.json` files are deleted by `python3 -m hooks._py.time_travel` at first post-migration write unless `recovery.time_travel.preserve_legacy: true` (moves to `.forge/runs/<run_id>/checkpoints/legacy-trash/`).

### Lifecycle

1. **Create:** `hooks/_py/time_travel` writes a checkpoint after each task completion (or at any point the orchestrator requests a save). Content-addressable: identical bundles across rewind-and-retry iterations dedup to a single on-disk directory; only `tree.json` grows an edge.

2. **Read:** On resume (`/forge-recover resume`), the orchestrator reads `HEAD` to find the active checkpoint and loads the four-tuple (state, worktree sha, events slice, memory) from `by-hash/`.

3. **Clean up:** Handled by `python3 -m hooks._py.time_travel gc`:
   - TTL-protected: any non-lineage node older than `retention_days`
   - Cap-enforced: oldest non-HEAD nodes evicted when `max_per_run` exceeded
   - Never deletes current HEAD itself, and skips entirely if the run is `RUNNING`/`PAUSED`/`ESCALATED`
   - `/forge-recover reset` clears the entire `.forge/runs/<run_id>/checkpoints/` tree for this run

### Survival Rules

- Checkpoints survive `/forge-recover resume` (that's their purpose)
- Checkpoints are cleared by `/forge-recover reset` and pipeline completion
- Checkpoints do NOT survive `rm -rf .forge/`

### recovery.time_travel (new in 1.9.0)

```yaml
recovery:
  time_travel:
    enabled: true                # master switch
    retention_days: 7            # GC TTL post-SHIP
    max_checkpoints_per_run: 100 # hard cap; oldest non-critical GC'd when exceeded
    require_clean_worktree: true # abort rewind if worktree dirty (safety)
    compression: zstd            # zstd | gzip | none (zstd falls back to gzip if stdlib-only)
    preserve_legacy: false       # archive pre-1.9.0 checkpoints to legacy-trash/ instead of deleting
```

---

### Task-level reflection fields

Each task object under `tasks[*]` carries:

| Field | Type | Required | Description |
|---|---|---|---|

**Cycle counter semantics (off-by-one guard):**

- `count == 0` means "no reflection dispatched yet." The FIRST critic dispatch happens at `count == 0`.
- On REVISE verdict within budget: increment count, re-enter GREEN, re-dispatch critic.
- With `max_cycles == 2`: up to 2 REVISEs → count reaches 2 → on next REVISE, budget exhausted, emit REFLECT-DIVERGENCE.

| Reflection # | Counter (before → after) | Verdict | Action |
|---|---|---|---|
| 1st dispatch | 0 → 0 | PASS | Proceed to REFACTOR. |
| 1st dispatch | 0 → 1 | REVISE | Re-enter GREEN; re-dispatch. |
| 2nd dispatch | 1 → 1 | PASS | Proceed to REFACTOR. |
| 2nd dispatch | 1 → 2 | REVISE | Budget exhausted. Emit REFLECT-DIVERGENCE WARNING. Proceed to REFACTOR. Reviewer panel decides at Stage 6. |

---

## Changelog

### 1.9.0 (Forge 3.1.0 — Self-Consistency Voting + Time-Travel Checkpoints)

**Self-consistency voting counters:**
- Add run-level `consistency_cache_hits` (integer, required). Incremented by `hooks/_py/consistency.py` on every cache hit.
- Add run-level `consistency_votes` (object, required). Keys: `shaper_intent`, `validator_verdict`, `pr_rejection_classification`. Each value: `{ "invocations": int, "cache_hits": int, "low_consensus": int }`. Incremented by the three callers (`fg-010-shaper`, `fg-210-validator`, `fg-710-post-run`). `validator_verdict.invocations` is NOT incremented on hard rule-pass verdicts (see `shared/consistency/voting.md` §6).
- New fields initialized to `0` / the per-decision skeleton object at PREFLIGHT. Pre-1.9.0 state.json files receive defaults via the standard migration ladder.

**Time-travel checkpoints (breaking):**
- **Breaking:** replace linear `.forge/checkpoint-{storyId}.json` files with a content-addressable DAG under `.forge/runs/<run_id>/checkpoints/`. Orchestrator refuses to proceed when `state.json.version` < `1.9.0`; no automatic migration (run `/forge-recover reset`).
- Add `state.json.checkpoints` (array, append-only, pre-rewind entries retained for audit) and `state.json.head_checkpoint` (mirrors `.forge/runs/<run_id>/checkpoints/HEAD`).
- Add `recovery.time_travel.*` config block (`enabled`, `retention_days`, `max_checkpoints_per_run`, `require_clean_worktree`, `compression`, `preserve_legacy`).
- Extend `recovery_op` payload values with `rewind` and `list-checkpoints`, backed by `hooks/_py/time_travel/` (CLI: `python3 -m hooks._py.time_travel`).
- Pseudo-state `REWINDING` appears only in `events.jsonl` `StateTransitionEvent` pairs that bracket a rewind op — never written to `state.story_state`.

### 1.8.0 (Forge 3.1.0)
- Add `tasks[*].implementer_reflection_cycles` (integer, required) for per-task Chain-of-Verification (CoVe) counter. Does NOT feed into `total_retries`, `total_iterations`, `verify_fix_count`, `test_cycles`, `quality_cycles`, or `implementer_fix_cycles`.
- Add `tasks[*].reflection_verdicts` (array, optional) audit trail, last 5 entries.
- Add run-level `implementer_reflection_cycles_total` and `reflection_divergence_count`.
- On `/forge-recover resume`: `reflection_verdicts` reset to `[]`; `implementer_reflection_cycles` preserved (budget not refunded mid-task).
- **Breaking (no backcompat):** new required fields initialized to 0 / [] at PREFLIGHT. Pre-1.8.0 state.json files are not readable by a 1.8.0+ orchestrator without PREFLIGHT re-init.

### 1.7.0 (Forge 3.0.0)
- Add `recovery_op` field to orchestrator input payload (skill surface consolidation).

## `eval_run` (added in 1.7.0)

Present only when the orchestrator was invoked with `--eval-mode <scenario_id>` (pipeline evaluation harness). Absent on normal runs.

```json
{
  "eval_run": {
    "scenario_id": "01-ts-microservice-greenfield",
    "started_at": "2026-04-19T12:00:00Z",
    "ended_at": "2026-04-19T12:10:00Z",
    "mode": "standard",
    "expected_token_budget": 150000,
    "expected_elapsed_seconds": 600,
    "touched_files_expected": ["src/server.ts", "src/routes/users.ts"]
  }
}
```

Field-name contract (review C2): `touched_files_expected` is the single canonical name used in both `state.json` and scenario `expected.yaml`. Do not introduce aliases.

## prompt_compaction

Added as an additive top-level `state.json` field in schema 1.9.0. Written by the
orchestrator when `code_graph.prompt_compaction.enabled: true`. Purely
observational; absence implies the feature is off. Because the block is
conditional and additive, no schema-version bump is required — consumers that
are unaware of `prompt_compaction` continue to work unchanged.

```json
{
  "prompt_compaction": {
    "enabled": true,
    "stages": {
      "orchestrator_preflight": {"budget": 8000, "pack_tokens": 6420, "files": 25, "ratio": 0.38},
      "planner_explore":        {"budget": 10000, "pack_tokens": 8930, "files": 25, "ratio": 0.42},
      "implementer_task_3":     {"budget": 4000, "pack_tokens": 3210, "files": 12, "ratio": 0.51}
    },
    "baseline_tokens_estimate": 22500,
    "baseline_source": "estimated",
    "compacted_tokens_total": 18560,
    "overall_ratio": 0.18,
    "bypass_events": {
      "sparse_graph": 0,
      "missing_graph": 0,
      "solve_diverged": 0,
      "corrupt_cache": 0
    }
  }
}
```

**Field semantics:**

- `ratio` per stage = `(baseline_tokens_estimate_for_stage - pack_tokens) / baseline_tokens_estimate_for_stage`.
- `baseline_source`:
  - `"estimated"` — computed analytically from `sum(size_bytes)/3.5` (default, always available; spec-review Issue #2 resolution).
  - `"measured"` — sourced from `.forge/run-history.db` averages once the run count ≥ 5.
- `overall_ratio` = `(baseline_tokens_estimate - compacted_tokens_total) / baseline_tokens_estimate`; `0` if baseline is `0`.
- `bypass_events` counts per run; SC-4's `repomap.bypass.failure` = sum of `missing_graph + solve_diverged + corrupt_cache` (excludes the legitimate `sparse_graph` path).

## Speculation fields

Speculative plan branches (`shared/speculation.md`) add two top-level
`state.json` fields. These are **additive** — no schema version bump — and
default to no-op values so unaware consumers ignore them.

```json
{
  "plan_candidates": [
    {
      "id": "cand-1",
      "emphasis_axis": "simplicity",
      "validator_verdict": "GO",
      "validator_score": 87,
      "selection_score": 87.3,
      "tokens": { "planner": 4120, "validator": 2080 },
      "selected": true
    }
  ],
  "speculation": {
    "triggered": true,
    "reasons": ["shaper_alternatives>=2", "confidence=MEDIUM"],
    "candidates_count": 3,
    "winner_id": "cand-1",
    "user_confirmed": false,
    "degraded": null
  }
}
```

**Defaults when speculation did not run:** `plan_candidates: []`, `speculation: null`.

`speculation.degraded` ∈ {`null`, `"low_diversity"`, `"cost_ceiling"`} — records fallback path reason.

**Field reference:**

| Field | Type | Notes |
|-------|------|-------|
| `plan_candidates[].id` | string | Candidate identifier, format `cand-{N}` (1-indexed). |
| `plan_candidates[].emphasis_axis` | string | Diversity axis steering the candidate (e.g. `simplicity`, `performance`, `safety`). |
| `plan_candidates[].validator_verdict` | string | `"GO"`, `"REVISE"`, or `"NO-GO"` from `fg-210-validator`. |
| `plan_candidates[].validator_score` | integer | Validator score (0-100). |
| `plan_candidates[].selection_score` | number | Tie-break-adjusted composite score used to pick the winner. |
| `plan_candidates[].tokens` | object | Token spend for this candidate, keyed by stage agent (`planner`, `validator`). |
| `plan_candidates[].selected` | boolean | `true` for the winner; exactly one candidate per run is `selected` when `speculation.triggered` is `true`. |
| `speculation.triggered` | boolean | `true` when branch mode ran for this run. |
| `speculation.reasons` | string[] | Trigger signals (e.g. `"shaper_alternatives>=2"`, `"confidence=MEDIUM"`). |
| `speculation.candidates_count` | integer | Number of candidates actually spawned (2 or 3). |
| `speculation.winner_id` | string | `id` of the selected candidate, or `""` if none selected. |
| `speculation.degraded` | string \| null | `null` (healthy), `"low_diversity"` (candidates too similar, fell back to single plan), or `"cost_ceiling"` (aborted due to token/cost budget). |

Candidate artifacts live under `.forge/plans/candidates/{run_id}/cand-{N}.json` and survive `/forge-recover reset`. See `shared/speculation.md` for the full workflow.

## Judge counters (Phase 5)

### `plan_judge_loops`

- **Type:** integer (≥ 0)
- **Scope:** root state
- **Default:** 0
- **Semantics:** Count of REVISE verdicts from fg-205-plan-judge for the current plan. Resets to 0 when a new plan is drafted (SHA of `requirement + approach` changes). Validator REVISE, user-continue, and feedback loops do NOT reset it.
- **Written by:** orchestrator (fg-100), via `shared/python/judge_plumbing.py::record_plan_judge_verdict`.

### `impl_judge_loops`

- **Type:** object keyed by `task_id`, values integer (≥ 0)
- **Scope:** root state
- **Default:** `{}`
- **Semantics:** Per-task REVISE counter from fg-301-implementer-judge.
- **Written by:** orchestrator, via `judge_plumbing.py::record_impl_judge_verdict`.

### `judge_verdicts`

- **Type:** array of `{judge_id, verdict, dispatch_seq, timestamp}`
- **Scope:** root state
- **Default:** `[]`
- **Semantics:** Audit log of every judge verdict in order. Used by retrospective (fg-700) to count REFLECT-DIVERGENCE and plan-rejection trends.
