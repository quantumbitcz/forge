# State Schema Reference

This document defines the JSON schemas and directory structure for the `.pipeline/` directory, which stores all per-run pipeline state. The `.pipeline/` directory is **gitignored** -- it persists on the local filesystem for run recovery and trend tracking but is never committed.

## Directory Structure

```
.pipeline/
+-- state.json                          # Root pipeline state (one per run)
+-- checkpoint-{storyId}.json           # Per-story recovery checkpoint
+-- stage_N_notes_{storyId}.md          # Per-stage decisions and findings (N = 0-9)
+-- stage_final_notes_{storyId}.md      # Retrospective summary for the run
+-- feedback/
|   +-- summary.md                      # Consolidated feedback (created when >20 entries)
|   +-- {date}-{topic}.md              # Individual feedback files (YYYY-MM-DD-topic.md)
|   +-- archive/                        # Incorporated feedback moved here
+-- docs-index.json                     # Documentation index (fallback when Neo4j unavailable)
+-- reports/
    +-- pipeline-{YYYY-MM-DD}.md       # Per-run retrospective report
    +-- recap-{YYYY-MM-DD}-{storyId}.md  # Human-readable run recap (by pl-720-recap)
```

### File Lifecycle

| File | Created At | Updated By | Survives Conversation? | Committed to Git? |
|------|-----------|-----------|----------------------|-------------------|
| `state.json` | Stage 0 (PREFLIGHT) | Orchestrator (every stage transition) | Yes (enables recovery) | No |
| `docs-index.json` | Stage 0 (PREFLIGHT) | `pl-130-docs-discoverer` | Yes | No |
| `checkpoint-*.json` | Stage 4 (IMPLEMENT) | Orchestrator (after each task) | Yes (enables resume) | No |
| `stage_N_notes_*.md` | Each stage | Stage agent | Yes | No |
| `stage_final_notes_*.md` | Stage 9 (LEARN) | Retrospective agent | Yes | No |
| `feedback/*.md` | On user correction | Feedback capture agent | Yes (pattern data) | No |
| `reports/pipeline-*.md` | Stage 9 (LEARN) | Retrospective agent | Yes (trend data) | No |
| `reports/recap-*.md` | Stage 9 (LEARN) | Recap agent (pl-720-recap) | Yes (project history) | No |

### Related Files (outside `.pipeline/`, committed to git)

| File | Location | Purpose |
|------|----------|---------|
| `pipeline-config.md` | `.claude/pipeline-config.md` | Mutable runtime parameters (auto-tuned by retrospective) |
| `pipeline-log.md` | `.claude/pipeline-log.md` | PREEMPT learnings + run history (institutional memory) |
| `dev-pipeline.local.md` | `.claude/dev-pipeline.local.md` | Static project config (commands, agents, conventions) |

---

## state.json

Root pipeline state file. Created at PREFLIGHT, updated at every stage transition. Used for interrupted-run detection and recovery.

### Schema

```json
{
  "version": "2.0.0",
  "complete": false,
  "story_id": "feat-plan-comments",
  "requirement": "Add plan comment feature",
  "domain_area": "plan",
  "risk_level": "MEDIUM",
  "story_state": "IMPLEMENTING",
  "active_component": "backend",
  "components": {
    "backend": {
      "story_state": "IMPLEMENTING",
      "conventions_hash": "ab12cd34",
      "conventions_section_hashes": {},
      "detected_versions": {
        "language_version": "2.0.0",
        "framework_version": "3.3.0"
      }
    },
    "frontend": {
      "story_state": "EXPLORING",
      "conventions_hash": "ef56gh78",
      "conventions_section_hashes": {},
      "detected_versions": {
        "language_version": "5.4.0",
        "framework_version": "18.2.0"
      }
    }
  },
  "quality_cycles": 0,
  "test_cycles": 0,
  "verify_fix_count": 0,
  "validation_retries": 0,
  "total_retries": 0,
  "total_retries_max": 10,
  "stage_timestamps": {
    "preflight": "2026-03-21T10:00:00Z",
    "explore": "2026-03-21T10:02:00Z"
  },
  "last_commit_sha": "abc123def456",
  "preempt_items_applied": ["check-openapi-before-controller"],
  "preempt_items_status": {
    "check-openapi-before-controller": { "applied": true, "false_positive": false }
  },
  "feedback_classification": "",
  "feedback_loop_count": 0,
  "score_history": [],
  "convergence": {
    "phase": "correctness",
    "phase_iterations": 0,
    "total_iterations": 0,
    "plateau_count": 0,
    "last_score_delta": 0,
    "convergence_state": "IMPROVING",
    "phase_history": [],
    "safety_gate_passed": false,
    "unfixable_findings": []
  },
  "integrations": {
    "linear": { "available": false, "team": "" },
    "playwright": { "available": false },
    "slack": { "available": false },
    "figma": { "available": false },
    "context7": { "available": false },
    "neo4j": { "available": false, "last_build_sha": "", "node_count": 0 }
  },
  "linear": {
    "epic_id": "",
    "story_ids": [],
    "task_ids": {}
  },
  "linear_sync": {
    "in_sync": true,
    "failed_operations": []
  },
  "modules": [],
  "cost": {
    "wall_time_seconds": 0,
    "stages_completed": 0
  },
  "recovery_applied": [],
  "recovery_budget": {
    "total_weight": 0.0,
    "max_weight": 5.0,
    "applications": []
  },
  "recovery": {
    "total_failures": 0,
    "total_recoveries": 0,
    "degraded_capabilities": [],
    "failures": [],
    "budget_warning_issued": false
  },
  "scout_improvements": 0,
  "conventions_hash": "",
  "conventions_section_hashes": {},
  "detected_versions": {
    "language": "kotlin",
    "language_version": "2.1.0",
    "framework": "spring",
    "framework_version": "3.4.1",
    "key_dependencies": {
      "exposed-core": "0.48.0",
      "kafka-clients": "3.7.0",
      "flyway-core": "10.8.1",
      "caffeine": "3.1.8"
    }
  },
  "check_engine_skipped": 0,
  "mode": "standard",
  "dry_run": false,
  "cross_repo": {},
  "spec": null,
  "documentation": {
    "discovery_error": false,
    "last_discovery_timestamp": "",
    "files_discovered": 0,
    "sections_parsed": 0,
    "decisions_extracted": 0,
    "constraints_extracted": 0,
    "code_linkages": 0,
    "coverage_gaps": [],
    "stale_sections": 0,
    "external_refs": [],
    "generation_history": [
      {
        "run_id": "",
        "timestamp": "",
        "types_generated": [],
        "confidence_changes": []
      }
    ]
  }
}
```

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | string | Yes | Schema version string (`"2.0.0"`). Enables schema compatibility checks — the recovery engine checks this before parsing. Schema version 2.0.0 is a clean break from v1.1.0 — adds `documentation` field as a required top-level object. Old state files from v1.x are incompatible — use `/pipeline-reset` to clear them. |
| `complete` | boolean | Yes | `false` while pipeline is running, `true` when Stage 9 finishes successfully. Used by PREFLIGHT to detect interrupted runs. |
| `story_id` | string | Yes | Kebab-case identifier for the current story. Derived from the requirement at PREFLIGHT (e.g., `"feat-plan-comments"`, `"fix-client-404"`, `"refactor-booking-validation"`). Used as suffix for checkpoint and notes files. |
| `requirement` | string | Yes | The original user requirement, verbatim. Captured from the `/pipeline-run` invocation argument. |
| `domain_area` | string | Yes | Primary domain area affected by this change. Set by the planner at Stage 2. Examples: `"plan"`, `"billing"`, `"scheduling"`, `"inventory"`, `"communication"`, `"user"`, `"workflow"`. |
| `risk_level` | string | Yes | Risk assessment from the planner. Valid values: `"LOW"`, `"MEDIUM"`, `"HIGH"`. Set at Stage 2, used at Stage 3 for the auto-proceed decision gate. |
| `story_state` | string | Yes | The overall pipeline state — the highest active stage across all components. If backend is IMPLEMENTING and frontend is EXPLORING, the top-level story_state is IMPLEMENTING. Valid values and transitions defined below. Updated at the start of each stage. |
| `active_component` | string | Yes | The component the orchestrator is currently processing. Set before dispatching agents for a component's tasks. Used by the check engine to route rules. Example: `"backend"`. |
| `components` | object | Yes | Per-component state tracking for monorepo and multi-stack projects. Keys are derived from `dev-pipeline.local.md` config: for single-component projects, the key is the component name from config (e.g., `"backend"`); for multi-component projects with `path:` fields, keys are the component names (e.g., `"backend"`, `"frontend"`, `"mobile"`). The top-level `story_state` is always the highest active stage across all components. Values are component state objects. See the [components section](#components-object-required) below. |
| `quality_cycles` | integer | Yes | Number of quality review cycles completed in Stage 6 (REVIEW). Starts at 0, incremented each time the quality gate dispatches fixes and rescores. Max is `quality_gate.max_review_cycles` from config. |
| `test_cycles` | integer | Yes | Number of test fix cycles completed in Stage 5 Phase B (test gate). Starts at 0, incremented each time failing tests are dispatched to the implementer. Max is `test_gate.max_test_cycles` from config. |
| `verify_fix_count` | integer | Yes | Number of build/lint fix attempts in Stage 5 Phase A. Starts at 0, incremented on each compile or lint failure that triggers an auto-fix. Max is `implementation.max_fix_loops` from config. |
| `validation_retries` | integer | Yes | Number of REVISE verdicts received at Stage 3 (VALIDATE). Starts at 0, incremented when the validator returns REVISE and the planner revises the plan. Max is `validation.max_validation_retries` from config (default: 2). |
| `total_retries` | integer | Yes | Cumulative retry count across all loops (validation_retries + verify_fix_count + test_cycles + quality_cycles + direct PR rejection increments). Used for the global retry budget. Starts at 0, incremented on every retry anywhere in the pipeline. |
| `total_retries_max` | integer | Yes | Global retry ceiling. Default: 10. Configurable in `pipeline-config.md`. When `total_retries >= total_retries_max`, the orchestrator escalates regardless of individual loop budgets. Constraint: >= 5 and <= 30. |
| `stage_timestamps` | object | Yes | Map of stage name (lowercase) to ISO 8601 timestamp marking when that stage started. Keys are: `"preflight"`, `"explore"`, `"plan"`, `"validate"`, `"implement"`, `"verify"`, `"review"`, `"docs"`, `"ship"`, `"learn"`. Only stages that have started appear in the map. |
| `last_commit_sha` | string | Yes | Git commit SHA of the most recent pipeline-created commit. Set after the pre-implement checkpoint commit (Stage 4) and updated after the final commit (Stage 8). Used by PREFLIGHT to detect git drift on interrupted-run recovery. Empty string `""` before the first commit. |
| `preempt_items_applied` | string[] | Yes | List of PREEMPT item identifiers from `pipeline-log.md` that were loaded at PREFLIGHT for the current domain area. Records what was *loaded*, not what was *used*. Empty array `[]` if no items match. |
| `preempt_items_status` | object | Yes | Tracks actual usage of PREEMPT items during implementation. Keys are item identifiers. Values: `{ "applied": true, "false_positive": false }` (item used and relevant), `{ "applied": false, "false_positive": true }` (item loaded but inapplicable). Populated by orchestrator from agent stage notes. Read by retrospective to update hit counts and confidence decay in `pipeline-log.md`. |
| `feedback_classification` | string | Yes | Feedback type from the most recent PR rejection. Valid values: `""` (no feedback), `"implementation"` (code-level feedback → re-enter Stage 4), `"design"` (design-level feedback → re-enter Stage 2). Set by orchestrator after reading `pl-710-feedback-capture` stage notes. |
| `feedback_loop_count` | integer | Yes | Consecutive PR rejections with the same `feedback_classification`. Starts at 0, incremented on each rejection where classification matches the previous one. Reset to 0 when classification changes. When `>= 2`, the orchestrator escalates with a feedback loop warning (see `stage-contract.md` Stage 8 cross-stage re-entry validation). |
| `score_history` | number[] | Yes | Quality score per review cycle for oscillation detection. Appended after each quality gate scoring. Used to detect regressions: if score drops by more than `oscillation_tolerance` between consecutive cycles, the orchestrator escalates. Integer with default scoring weights; may be non-integer with custom weights. |
| `convergence` | object | Yes | Convergence engine state. Tracks two-phase iteration progress (correctness → perfection → safety gate). See `shared/convergence-engine.md` for full algorithm. Initialized at PREFLIGHT with all counters at 0. |
| `convergence.phase` | string | Yes | Current convergence phase. Valid values: `"correctness"` (Phase 1 — IMPLEMENT ↔ VERIFY), `"perfection"` (Phase 2 — IMPLEMENT ↔ REVIEW), `"safety_gate"` (final VERIFY after Phase 2). Transitions managed by the convergence engine. |
| `convergence.phase_iterations` | integer | Yes | Iteration count within the current phase. Resets to 0 on phase transition. |
| `convergence.total_iterations` | integer | Yes | Cumulative iteration count across all phases. Never resets. Feeds into `total_retries` budget — each increment also increments `total_retries`. |
| `convergence.plateau_count` | integer | Yes | Consecutive Phase 2 cycles where score improved by <= `plateau_threshold`. Resets to 0 on any improvement > `plateau_threshold`. When >= `plateau_patience`, convergence is declared. |
| `convergence.last_score_delta` | integer | Yes | Score change from the previous cycle (`current_score - previous_score`). 0 on first cycle. Used for convergence state classification. |
| `convergence.convergence_state` | string | Yes | Current convergence classification. Valid values: `"IMPROVING"` (score increasing meaningfully), `"PLATEAUED"` (score stalled — convergence declared), `"REGRESSING"` (score dropped beyond tolerance — escalate). |
| `convergence.phase_history` | array | Yes | Append-only log of completed phases. Each entry: `{ "phase": "<name>", "iterations": <int>, "outcome": "converged"\|"failed"\|"escalated", "duration_seconds": <int> }`. Used by retrospective for trend analysis. |
| `convergence.safety_gate_passed` | boolean | Yes | `true` when the final VERIFY after Phase 2 passes. `false` until then. If safety gate fails, phase transitions back to correctness and this resets to `false`. |
| `convergence.unfixable_findings` | array | Yes | Findings that survived all iterations with documented rationale. Each entry: `{ "category": "<CATEGORY-CODE>", "file": "<path>", "line": <int>, "severity": "<CRITICAL\|WARNING\|INFO>", "reason": "<why not fixed>", "options": ["<option1>", "<option2>"] }`. Populated when Phase 2 converges below target. |
| `integrations` | object | Yes | Detected MCP integration availability. Populated at PREFLIGHT by probing for each MCP server. Each key is an integration name with an `available` boolean. The `linear` integration also includes a `team` string (Linear team key). The `neo4j` integration includes `last_build_sha` (SHA of the commit the graph was built from) and `node_count` (total nodes in the graph) — set by the `graph-init` skill; when available, the orchestrator pre-queries graph context at stage boundaries. Used by agents to conditionally use integrations (e.g., create Linear issues, post Slack messages). |
| `linear` | object | Yes | Linear project management state for the current run. `epic_id`: Linear epic ID if the pipeline run is tracked as an epic (empty string if Linear unavailable). `story_ids`: array of Linear issue IDs created for pipeline stories. `task_ids`: map of task ID (e.g., `"T001"`) to Linear sub-issue ID. Populated during PLAN and IMPLEMENT stages. |
| `modules` | object[] | Yes | Per-module state for multi-module projects. Each entry: `{ "module": "spring", "story_state": "IMPLEMENTING", "story_id": "story-1" }`. Each entry's `story_state` can also be `"FAILED"` (terminal — module failed after max retries) or `"BLOCKED"` (waiting on a dependency module to complete). Blocked modules include a `blocked_by` field with the failing module name (e.g., `{ "module": "react", "story_state": "BLOCKED", "story_id": "story-2", "blocked_by": "spring" }`). The orchestrator manages transitions: backend modules complete through VERIFY before frontend enters IMPLEMENT. Empty array for single-module projects (use `components` for per-component state instead). |
| `cost` | object | Yes | Pipeline run cost tracking. `wall_time_seconds`: total elapsed wall-clock time from PREFLIGHT start to current stage (updated at each stage transition). `stages_completed`: count of stages that have finished (0-10). Used by the retrospective for trend analysis and by the orchestrator for timeout detection. |
| `recovery_applied` | string[] | Yes | Derived view of recovery strategy names applied during this run. Derived from `recovery_budget.applications`: `recovery_applied = recovery_budget.applications.map(a => a.strategy)`. Kept for backward compatibility. Updated at every budget write. |
| `recovery_budget` | object | Yes | Weighted recovery budget tracking. `total_weight`: sum of all applied strategy weights. `max_weight`: budget ceiling (default: 5.0). `applications[]`: list of `{ "strategy": "<name>", "weight": <float>, "stage": "<stage>", "timestamp": "<ISO8601>" }`. Strategy weights: transient-retry=0.5, tool-diagnosis=1.0, state-reconstruction=1.5, agent-reset=1.0, dependency-health=1.0, resource-cleanup=0.5, graceful-stop=0.0. When `total_weight >= max_weight`, escalate. When `total_weight > 4.0` (80%), set `recovery.budget_warning_issued: true`. |
| `linear_sync` | object | Yes | Tracks Linear API operation success/failure for desync detection. `in_sync`: boolean, true when all Linear operations succeeded. `failed_operations[]`: list of `{ "op": "<operation>", "error": "<message>", "timestamp": "<ISO8601>" }`. Read by retrospective to report desync. |
| `scout_improvements` | integer | Yes | Count of Boy Scout improvements made during implementation — small cleanup changes (unused imports, variable renames, helper extractions) applied opportunistically while modifying files. Tracked as `SCOUT-*` findings in the quality gate (no point deduction). Reported in the retrospective. |
| `conventions_hash` | string | Yes | SHA256 first 8 chars of full conventions_file content at PREFLIGHT. Kept for backward compatibility. Agents should prefer `conventions_section_hashes` for granular drift detection. Empty if conventions file was unavailable. |
| `conventions_section_hashes` | object | Yes | Per-section SHA256 hashes (first 8 chars) of conventions_file content at PREFLIGHT. Keys are section names (e.g., `"architecture"`, `"naming"`, `"testing"`), values are hash strings. Enables granular drift detection — agents only react to changes in their relevant section. If conventions file was unavailable, set to `{}`. |
| `detected_versions` | object | Yes | Project dependency versions detected at PREFLIGHT. `language`: detected language (e.g., "kotlin", "typescript"). `language_version`: language/compiler version. `framework`: primary framework (e.g., "spring-boot", "fastapi"). `framework_version`: framework version. `key_dependencies` (v1.1.0): map of dependency name to version string for all detected libraries across all layers (language, framework, databases, messaging, persistence, testing). Values are `""` or `"unknown"` when detection fails — in that case, version-gated rules default to applying (conservative). Example: `{ "exposed-core": "0.48.0", "kafka-clients": "3.7.0", "flyway-core": "10.8.1", "caffeine": "3.1.8" }` |
| `check_engine_skipped` | integer | Yes | Count of inline check engine invocations that were skipped due to timeout or error during the current run. The `engine.sh` hook writes a counter to `.pipeline/.check-engine-skipped` on failure. The orchestrator copies this value to state.json at VERIFY Phase A entry, then deletes the marker file. Informational — VERIFY runs full checks regardless. |
| `mode` | string | Yes | Pipeline execution mode detected from requirement prefix. Valid values: `"standard"` (default), `"migration"` (requirement starts with `migrate:` or `migration:`), `"bootstrap"` (requirement starts with `bootstrap:`). Determines which planner agent is dispatched at Stage 2. |
| `abort_reason` | string | No | Reason the pipeline was aborted. Set when the orchestrator auto-aborts (e.g., `"NO-GO timeout"`, `"budget exhausted"`). Empty string or absent when not aborted. Present only in terminal state (`complete: true`). |
| `dry_run` | boolean | Yes | `true` when pipeline was invoked with `--dry-run` flag. Gates IMPLEMENT entry — if true, stages 4-9 are skipped and the pipeline outputs a dry-run report after VALIDATE. Default: `false`. |
| `cross_repo` | object | No | Tracks cross-repo worktrees and status when `related_projects` is configured. Keys are project names; values contain `path`, `branch`, `status`, `files_changed`, and `pr_url`. See the [cross_repo section](#cross_repo-object-optional) above. Omitted when no cross-repo tasks exist. |
| `spec` | object\|null | No | Present when pipeline was invoked with `--spec <path>`. Contains `path`, `epic_title`, `story_count`, and `loaded_at`. `null` when not using spec-driven invocation. See the [spec section](#spec-object-optional) above. |
| `documentation` | object | Yes | Documentation subsystem state. Populated by `pl-130-docs-discoverer` at PREFLIGHT and updated by `pl-350-docs-generator` at DOCUMENTING. |
| `documentation.discovery_error` | boolean | Yes | `true` if `pl-130-docs-discoverer` timed out or failed during PREFLIGHT (documentation enabled but discovery failed). Default: `false`. When true, downstream agents (pl-350, docs-consistency-reviewer) operate with degraded context — skip cross-referencing and coverage gap analysis. |
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
- Cleaned up by `/pipeline-rollback` or `/pipeline-reset`

---

### spec (object, optional)

Present when pipeline was invoked with `--spec <path>`. Stores parsed spec metadata.

```json
{
  "spec": {
    "path": "string — path to the spec file",
    "epic_title": "string — extracted epic title",
    "story_count": "number — count of stories in spec",
    "loaded_at": "string — ISO 8601 timestamp"
  }
}
```

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
      }
    },
    "frontend": {
      "story_state": "EXPLORING",
      "conventions_hash": "ef56gh78",
      "conventions_section_hashes": {},
      "detected_versions": {
        "language_version": "5.4.0",
        "framework_version": "18.2.0"
      }
    }
  }
}
```

Extended example (v1.1.0) showing `path` and `convention_stack`:

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
- `story_state` — current pipeline stage for this component (same enum as top-level)
- `conventions_hash` — SHA256 first 8 chars of the composed convention stack
- `conventions_section_hashes` — per-section hashes for drift detection
- `detected_versions` — extracted from manifest files in the component path
- `score_history` — `number[]`, default `[]`. Per-component quality score history for oscillation tracking. Populated during REVIEW.
- `convention_stack` (optional, v1.1.0) — array of resolved convention file paths in composition order. Populated by PREFLIGHT. Empty array if not yet resolved.
- `path` (optional, v1.1.0) — relative path prefix for this component. Used by the check engine for per-file convention routing. Required in multi-service mode. Defaults to project root in single-service mode.

---

### active_component (string, required)

The component the orchestrator is currently processing. Set before dispatching agents for a component's tasks. Used by the check engine to route rules.

Example: `"active_component": "backend"`

---

### Required Fields

The following fields are required in every v2.0.0 state.json:

`version`, `complete`, `story_id`, `story_state`, `components`, `active_component`, `total_retries`, `total_retries_max`

All other fields in the Field Reference table marked "Yes" are also required; the list above is the minimum set the recovery engine validates on load.

---

### Migration State (stored in `state.json.migration` during migration runs)

During migration mode (triggered by `/migration` or `/pipeline-run "migrate: ..."`), the `migration` object is added to `state.json` by `pl-160-migration-planner`. This object tracks the full lifecycle of a migration run, including version detection, impact analysis, and per-phase progress.

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

**Note:** Version 1.0.0 is a clean break. Old state files from previous schema versions are incompatible — use `/pipeline-reset` to clear them. The recovery engine checks the `version` field before parsing and will refuse to load state files with a different version.

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

Migration states are used exclusively by `pl-160-migration-planner` during `/migration` runs. They are not part of the standard pipeline flow.

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
  "last_action": "pl-300-implementer completed T002",
  "timestamp": "2026-03-21T10:15:00Z"
}
```

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `storyId` | string | Yes | Story identifier matching `state.json.story_id`. Used to correlate checkpoint with the run. |
| `stage` | integer | Yes | Pipeline stage number (0-9) at which this checkpoint was written. Typically `4` (IMPLEMENT), but may be updated during VERIFY/REVIEW retry loops. |
| `current_group` | integer | Yes | The parallel group currently being executed (1-indexed). Groups are sequential; tasks within a group may be parallel. Valid range: 1 to max 3 (plan defines up to 3 parallel groups). |
| `tasks_completed` | array | Yes | List of completed task objects. Each object contains the fields described below. Ordered by completion time. |
| `tasks_completed[].taskId` | string | Yes | Task identifier from the plan (e.g., `"T001"`, `"T002"`). |
| `tasks_completed[].status` | string | Yes | Task outcome. Valid values: `"pass"` (task completed successfully), `"fail"` (task failed after max fix attempts), `"skipped"` (task skipped due to dependency failure). |
| `tasks_completed[].files_created` | string[] | Yes | Relative paths of files created by this task. Empty array if no new files. |
| `tasks_completed[].files_modified` | string[] | Yes | Relative paths of files modified by this task (excluding files listed in `files_created`). Empty array if no modifications. |
| `tasks_completed[].fix_attempts` | integer | Yes | Number of fix attempts for this task (0 = succeeded on first try). Max is `implementation.max_fix_loops` from config. |
| `tasks_completed[].preempt_items_used` | string[] | Yes | PREEMPT item identifiers that were applied during this task. Empty array if none. Used by the orchestrator to populate `state.json.preempt_items_status`. |
| `tasks_remaining` | string[] | Yes | Task IDs not yet started. Shrinks as tasks complete. Empty array when all tasks are done. |
| `last_action` | string | Yes | Human-readable description of the most recent action taken. Used for logging and recovery context. Examples: `"pl-310-scaffolder generated T003 boilerplate"`, `"pl-300-implementer completed T002"`, `"build fix attempt 2 for T004"`. |
| `timestamp` | string | Yes | ISO 8601 timestamp of when this checkpoint was last written. Used to determine freshness during recovery. |

### Recovery Behavior

When PREFLIGHT detects an interrupted run (`.pipeline/state.json` exists with `complete: false`):

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

Written by the retrospective agent at Stage 9. Contains the run summary, extracted learnings, and tuning recommendations. This is the primary input for `pipeline-log.md` updates.

---

## Feedback Directory

### feedback/{date}-{topic}.md

Individual feedback files created by `pl-710-feedback-capture` when the user corrects the pipeline's approach. Format:

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

Contains individual feedback files that have been consolidated into `summary.md` or applied as PREEMPT items in `pipeline-log.md`. Preserved for audit trail.

---

## Reports Directory

### reports/pipeline-{YYYY-MM-DD}.md

Per-run retrospective report written by `pl-700-retrospective` at Stage 9. Contains:

- Run metadata (story_id, requirement, duration, risk_level)
- Stage-by-stage timing breakdown
- Quality gate results (score history, final verdict, finding summary)
- Test gate results (pass/fail, cycles needed, coverage delta)
- Fix loop statistics (verify_fix_count, quality_cycles, test_cycles)
- Extracted learnings (PREEMPT, PATTERN, TUNING)
- Auto-tuning actions taken
- Comparison against previous runs (trend data)

If multiple runs occur on the same date, reports use a suffix: `pipeline-{YYYY-MM-DD}-2.md`, `pipeline-{YYYY-MM-DD}-3.md`.

### reports/recap-{YYYY-MM-DD}-{storyId}.md

Human-readable run recap written by `pl-720-recap` at Stage 9, after the retrospective. Contains:

- What was built (per-story summary with file lists)
- Key decisions made (with trade-off reasoning)
- Boy Scout improvements (SCOUT-* findings)
- Unfixed findings (with explanation and follow-up tickets)
- Pipeline metrics (files, tests, fix cycles, score progression)
- Learnings captured (PREEMPT items added/updated)

If Linear is available, a summarized version (max 2,000 chars) is posted as a comment on the Epic. If a PR exists, the "What Was Built" and "Key Decisions" sections are appended to the PR description.
