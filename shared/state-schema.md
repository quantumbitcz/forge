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
+-- reports/
    +-- pipeline-{YYYY-MM-DD}.md       # Per-run retrospective report
    +-- recap-{YYYY-MM-DD}-{storyId}.md  # Human-readable run recap (by pl-720-recap)
```

### File Lifecycle

| File | Created At | Updated By | Survives Conversation? | Committed to Git? |
|------|-----------|-----------|----------------------|-------------------|
| `state.json` | Stage 0 (PREFLIGHT) | Orchestrator (every stage transition) | Yes (enables recovery) | No |
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
  "version": "1.1",
  "complete": false,
  "story_id": "feat-plan-comments",
  "requirement": "Add plan comment feature",
  "domain_area": "plan",
  "risk_level": "MEDIUM",
  "story_state": "IMPLEMENTING",
  "quality_cycles": 0,
  "test_cycles": 0,
  "verify_fix_count": 0,
  "validation_retries": 0,
  "stage_timestamps": {
    "preflight": "2026-03-21T10:00:00Z",
    "explore": "2026-03-21T10:02:00Z"
  },
  "last_commit_sha": "abc123def456",
  "preempt_items_applied": ["check-openapi-before-controller"],
  "integrations": {
    "linear": { "available": false, "team": "" },
    "playwright": { "available": false },
    "slack": { "available": false },
    "figma": { "available": false },
    "context7": { "available": false }
  },
  "linear": {
    "epic_id": "",
    "story_ids": [],
    "task_ids": {}
  },
  "modules": [],
  "cost": {
    "wall_time_seconds": 0,
    "stages_completed": 0
  },
  "recovery_applied": [],
  "scout_improvements": 0
}
```

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `complete` | boolean | Yes | `false` while pipeline is running, `true` when Stage 9 finishes successfully. Used by PREFLIGHT to detect interrupted runs. |
| `story_id` | string | Yes | Kebab-case identifier for the current story. Derived from the requirement at PREFLIGHT (e.g., `"feat-plan-comments"`, `"fix-client-404"`, `"refactor-booking-validation"`). Used as suffix for checkpoint and notes files. |
| `requirement` | string | Yes | The original user requirement, verbatim. Captured from the `/pipeline-run` invocation argument. |
| `domain_area` | string | Yes | Primary domain area affected by this change. Set by the planner at Stage 2. Examples: `"plan"`, `"billing"`, `"coaching"`, `"communication"`, `"enterprise"`, `"user"`, `"workflow"`. |
| `risk_level` | string | Yes | Risk assessment from the planner. Valid values: `"LOW"`, `"MEDIUM"`, `"HIGH"`. Set at Stage 2, used at Stage 3 for the auto-proceed decision gate. |
| `story_state` | string | Yes | Current pipeline stage. Valid values and transitions defined below. Updated at the start of each stage. |
| `quality_cycles` | integer | Yes | Number of quality review cycles completed in Stage 6 (REVIEW). Starts at 0, incremented each time the quality gate dispatches fixes and rescores. Max is `quality_gate.max_review_cycles` from config. |
| `test_cycles` | integer | Yes | Number of test fix cycles completed in Stage 5 Phase B (test gate). Starts at 0, incremented each time failing tests are dispatched to the implementer. Max is `test_gate.max_test_cycles` from config. |
| `verify_fix_count` | integer | Yes | Number of build/lint fix attempts in Stage 5 Phase A. Starts at 0, incremented on each compile or lint failure that triggers an auto-fix. Max is `implementation.max_fix_loops` from config. |
| `validation_retries` | integer | Yes | Number of REVISE verdicts received at Stage 3 (VALIDATE). Starts at 0, incremented when the validator returns REVISE and the planner revises the plan. Max is `validation.max_validation_retries` from config (default: 2). |
| `stage_timestamps` | object | Yes | Map of stage name (lowercase) to ISO 8601 timestamp marking when that stage started. Keys are: `"preflight"`, `"explore"`, `"plan"`, `"validate"`, `"implement"`, `"verify"`, `"review"`, `"docs"`, `"ship"`, `"learn"`. Only stages that have started appear in the map. |
| `last_commit_sha` | string | Yes | Git commit SHA of the most recent pipeline-created commit. Set after the pre-implement checkpoint commit (Stage 4) and updated after the final commit (Stage 8). Used by PREFLIGHT to detect git drift on interrupted-run recovery. Empty string `""` before the first commit. |
| `preempt_items_applied` | string[] | Yes | List of PREEMPT item identifiers from `pipeline-log.md` that were applied during this run. Populated at PREFLIGHT when matching PREEMPT items are found for the domain area. Empty array `[]` if no items match. |
| `version` | string | Yes | Schema version string (e.g., `"1.1"`). Enables schema migration — the recovery engine checks this before parsing to ensure compatibility with the current engine version. |
| `integrations` | object | Yes | Detected MCP integration availability. Populated at PREFLIGHT by probing for each MCP server. Each key is an integration name with an `available` boolean. The `linear` integration also includes a `team` string (Linear team key). Used by agents to conditionally use integrations (e.g., create Linear issues, post Slack messages). |
| `linear` | object | Yes | Linear project management state for the current run. `epic_id`: Linear epic ID if the pipeline run is tracked as an epic (empty string if Linear unavailable). `story_ids`: array of Linear issue IDs created for pipeline stories. `task_ids`: map of task ID (e.g., `"T001"`) to Linear sub-issue ID. Populated during PLAN and IMPLEMENT stages. |
| `modules` | object[] | Yes | Per-module state for multi-module projects. Each entry: `{ "module": "kotlin-spring", "story_state": "IMPLEMENTING", "story_id": "story-1" }`. The orchestrator manages transitions: backend modules complete through VERIFY before frontend enters IMPLEMENT. Empty array for single-module projects (main `story_state` field is used instead). |
| `cost` | object | Yes | Pipeline run cost tracking. `wall_time_seconds`: total elapsed wall-clock time from PREFLIGHT start to current stage (updated at each stage transition). `stages_completed`: count of stages that have finished (0-10). Used by the retrospective for trend analysis and by the orchestrator for timeout detection. |
| `recovery_applied` | string[] | Yes | List of recovery strategy names applied during this run (e.g., `["transient-retry", "tool-diagnosis"]`). Appended each time the recovery engine applies a strategy. Used to enforce the recovery budget (max 5 total applications per run). |
| `scout_improvements` | integer | Yes | Count of Boy Scout improvements made during implementation — small cleanup changes (unused imports, variable renames, helper extractions) applied opportunistically while modifying files. Tracked as `SCOUT-*` findings in the quality gate (no point deduction). Reported in the retrospective. |

**Note:** The `version` field enables schema migration. Recovery engine checks this before parsing. If the `version` field is missing (pre-1.1 state files), the recovery engine treats it as version `"1.0"` and applies forward migration (adding new fields with default values) before proceeding.

### story_state Valid Values

| Value | Stage | Description |
|-------|-------|-------------|
| `"PREFLIGHT"` | 0 | Config loading, state initialization, interrupted-run check |
| `"EXPLORING"` | 1 | Codebase exploration agents running |
| `"PLANNING"` | 2 | Planner decomposing requirement into stories and tasks |
| `"VALIDATING"` | 3 | Validator reviewing plan from 5 perspectives |
| `"IMPLEMENTING"` | 4 | Scaffolder and implementer writing code per task |
| `"VERIFYING"` | 5 | Build, lint, and test verification |
| `"REVIEWING"` | 6 | Quality gate agents reviewing code |
| `"DOCUMENTING"` | 7 | Documentation updates (CLAUDE.md, KDoc/TSDoc) |
| `"SHIPPING"` | 8 | Branch creation, commit, PR |
| `"LEARNING"` | 9 | Retrospective analysis, config tuning, report generation |

### story_state Transitions

The normal flow is linear: `PREFLIGHT -> EXPLORING -> PLANNING -> VALIDATING -> IMPLEMENTING -> VERIFYING -> REVIEWING -> DOCUMENTING -> SHIPPING -> LEARNING`.

Valid retry loops:
- `VALIDATING -> PLANNING` (REVISE verdict, up to `validation.max_validation_retries`)
- `VERIFYING -> IMPLEMENTING` (test failures dispatched to implementer, up to `test_gate.max_test_cycles`)
- `REVIEWING -> IMPLEMENTING` (quality fix cycle, up to `quality_gate.max_review_cycles`)
- `SHIPPING -> IMPLEMENTING` (user rejects PR with feedback, resets quality and test counters)

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
      "fix_attempts": 0
    },
    {
      "taskId": "T002",
      "status": "pass",
      "files_created": [],
      "files_modified": ["core/impl/plan/ICreatePlanCommentUseCaseImpl.kt"],
      "fix_attempts": 1
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
