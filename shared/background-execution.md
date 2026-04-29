# Background Execution

Defines the contract for running the forge pipeline asynchronously. When activated, the orchestrator writes structured progress artifacts to `.forge/progress/` instead of interactive UI, enabling detached execution with periodic status polling.

## Activation

The `--background` flag on `/forge run` activates background mode:

    /forge run --background "Add user profile endpoint"

Background mode sets `state.json.background: true` at PREFLIGHT. The orchestrator suppresses all `AskUserQuestion` calls and replaces interactive task updates with file-based progress artifacts. Autonomous mode (`autonomous: true`) is implied — all decisions use recommended defaults logged with `[AUTO]` prefix.

Background mode is incompatible with `--dry-run` (dry-run requires no worktree or artifacts). If both flags are provided, `--dry-run` takes precedence and background mode is ignored.

## Progress Artifacts

All progress files live under `.forge/progress/`. The directory is created at PREFLIGHT when `background: true`. Files are ephemeral — they do not survive `/forge-admin recover reset` and are not committed to git.

```
.forge/progress/
+-- status.json              # Current pipeline state snapshot
+-- timeline.jsonl           # Append-only event log
+-- stage-summary/           # Completed stage summaries
|   +-- 0-PREFLIGHT.json
|   +-- 1-EXPLORE.json
|   +-- ...
+-- alerts.json              # Escalation points requiring user attention
```

### status.json

Updated by the orchestrator at every stage transition, convergence iteration, and significant progress event. This is the primary polling target for `/forge-ask status`.

```json
{
  "run_id": "run-2026-04-12-abc123",
  "stage": "REVIEWING",
  "stage_number": 6,
  "progress_pct": 65,
  "score": 88,
  "convergence_phase": "perfection",
  "convergence_iteration": 2,
  "started_at": "2026-04-12T10:00:00Z",
  "last_update": "2026-04-12T10:14:32Z",
  "eta_minutes": 8,
  "alerts": [
    {
      "type": "CONCERNS",
      "message": "Score 72 in CONCERNS range after review round 1",
      "timestamp": "2026-04-12T10:12:00Z"
    }
  ],
  "model_usage": {
    "opus": { "dispatches": 3, "tokens_in": 45000, "tokens_out": 12000 },
    "sonnet": { "dispatches": 8, "tokens_in": 120000, "tokens_out": 35000 }
  }
}
```

#### Status Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `run_id` | string | yes | Unique run identifier (matches `state.json.run_id`) |
| `stage` | string | yes | Current stage name (e.g. `REVIEWING`, `IMPLEMENTING`) |
| `stage_number` | integer | yes | Stage index 0-9 |
| `progress_pct` | integer | yes | Estimated overall progress 0-100. Calculated as `(stage_number * 10) + intra_stage_pct` |
| `score` | integer or null | yes | Latest quality score (null before first review) |
| `convergence_phase` | string or null | yes | Current convergence phase (`correctness`, `perfection`, or null if pre-convergence) |
| `convergence_iteration` | integer | yes | Current iteration within the convergence phase |
| `started_at` | string (ISO 8601) | yes | Pipeline start time |
| `last_update` | string (ISO 8601) | yes | Timestamp of last status write |
| `eta_minutes` | integer or null | no | Estimated minutes remaining (null if not calculable) |
| `alerts` | array | yes | Active alerts awaiting user attention (subset of `alerts.json`) |
| `model_usage` | object | yes | Token usage per model tier |

### timeline.jsonl

One JSON object per line, append-only. Every significant pipeline event is recorded as a timeline entry. This provides a full audit trail of the background run.

```jsonl
{"ts":"2026-04-12T10:00:00Z","event":"pipeline_start","stage":"PREFLIGHT","detail":"Background mode activated"}
{"ts":"2026-04-12T10:00:05Z","event":"stage_enter","stage":"PREFLIGHT","detail":"Config loaded, 3 components"}
{"ts":"2026-04-12T10:00:45Z","event":"stage_exit","stage":"PREFLIGHT","detail":"Worktree created at .forge/worktree"}
{"ts":"2026-04-12T10:01:00Z","event":"stage_enter","stage":"EXPLORING","detail":"Dispatching explore agents"}
{"ts":"2026-04-12T10:03:00Z","event":"agent_dispatch","stage":"EXPLORING","agent":"fg-200-planner","model":"sonnet"}
{"ts":"2026-04-12T10:10:00Z","event":"score_update","stage":"REVIEWING","score":88,"detail":"Review round 1 complete"}
{"ts":"2026-04-12T10:12:00Z","event":"alert","stage":"REVIEWING","alert_type":"CONCERNS","detail":"Score 72 in CONCERNS range"}
{"ts":"2026-04-12T10:20:00Z","event":"pipeline_end","stage":"LEARNING","detail":"Run complete, PR created"}
```

#### Timeline Event Types

| Event | Description |
|-------|-------------|
| `pipeline_start` | Run begins |
| `pipeline_end` | Run completes (success or abort) |
| `stage_enter` | Orchestrator enters a new stage |
| `stage_exit` | Orchestrator exits a stage |
| `agent_dispatch` | Agent dispatched (includes `agent` and `model` fields) |
| `agent_complete` | Agent returns (includes `agent` field) |
| `score_update` | Quality score changed (includes `score` field) |
| `convergence_transition` | Phase changed (includes `from_phase` and `to_phase`) |
| `alert` | Escalation point reached (includes `alert_type`) |
| `alert_resolved` | User resolved an alert |
| `recovery` | Recovery strategy applied (includes `strategy`) |
| `error` | Non-recoverable error (includes `error_type`) |

### stage-summary/

After each stage completes, the orchestrator writes a summary file named `{N}-{STAGE_NAME}.json`:

```json
{
  "stage": "REVIEWING",
  "stage_number": 6,
  "started_at": "2026-04-12T10:08:00Z",
  "completed_at": "2026-04-12T10:14:32Z",
  "duration_seconds": 392,
  "agents_dispatched": ["fg-400-quality-gate", "fg-410-code-reviewer", "fg-411-security-reviewer"],
  "findings_count": { "CRITICAL": 0, "WARNING": 2, "INFO": 5 },
  "score_before": 82,
  "score_after": 88,
  "notes": "Two WARNING findings in SEC-* category. No CRITICAL issues."
}
```

### alerts.json

Contains escalation points that require user attention. The orchestrator pauses execution when an alert is written and waits for resolution.

```json
{
  "alerts": [
    {
      "id": "alert-001",
      "type": "REGRESSING",
      "severity": "CRITICAL",
      "stage": "VERIFYING",
      "timestamp": "2026-04-12T10:12:00Z",
      "message": "Score dropped from 85 to 62 after implementation cycle 3",
      "context": {
        "score_before": 85,
        "score_after": 62,
        "iteration": 3
      },
      "options": [
        { "id": "continue", "label": "Continue with current approach" },
        { "id": "revert", "label": "Revert last implementation cycle" },
        { "id": "abort", "label": "Abort pipeline run" }
      ],
      "resolved": false,
      "resolution": null
    }
  ]
}
```

#### Alert Types

| Type | Severity | Trigger |
|------|----------|---------|
| `REGRESSING` | CRITICAL | Score dropped below previous iteration by more than `oscillation_tolerance` |
| `CONCERNS` | WARNING | Score in CONCERNS range (60-79) after convergence phase |
| `UNRECOVERABLE_CRITICAL` | CRITICAL | Unresolved CRITICAL finding after max fix attempts |
| `RECOVERY_EXHAUSTED` | CRITICAL | Recovery budget exceeded (total weight > 5.5) |
| `SAFETY_ESCALATION` | CRITICAL | Safety gate triggered (E1-E4 error categories) |
| `BUILD_FAILURE` | WARNING | Build/lint/test failure after 3 consecutive attempts |
| `USER_INPUT_REQUIRED` | INFO | Decision point that cannot be auto-resolved in autonomous mode |

## Escalation Behavior

When the orchestrator encounters a condition that would normally trigger `AskUserQuestion` in interactive mode, background mode handles it as follows:

1. **Auto-resolvable decisions**: Resolved automatically using the recommended default (same as `autonomous: true`). Logged with `[AUTO]` prefix in timeline.
2. **Safety escalations**: Written to `alerts.json` with `resolved: false`. The pipeline **pauses** at the current stage and polls `alerts.json` every 30 seconds for resolution.
3. **Resolution**: The user (via `/forge-ask status`, Slack notification, or direct file edit) sets `resolved: true` and `resolution` to the chosen option ID. The orchestrator reads the resolution and continues.

### Pause behavior

When paused on an alert:
- `status.json.stage` remains at the current stage
- `status.json.progress_pct` stops advancing
- `timeline.jsonl` records the pause event
- The `.forge/.lock` file remains held (prevents concurrent runs)
- The pipeline resumes within 30 seconds of alert resolution

### Timeout

If an alert remains unresolved for 60 minutes (configurable via `background.alert_timeout_minutes`), the orchestrator aborts the run gracefully:
1. Writes `pipeline_end` event to timeline with `detail: "Alert timeout"`
2. Sets `state.json.complete: true` with `story_state: "ABORTED"`
3. Preserves all artifacts for `/forge-admin recover resume`

## User Interaction

### /forge-ask status

In background mode, `/forge-ask status` reads `.forge/progress/status.json` and displays:
- Current stage and progress percentage
- Quality score and convergence state
- Active alerts (if any) with resolution options
- Model usage summary
- ETA (if available)

The `--watch` flag polls `status.json` at a configurable interval (default 5 seconds) and refreshes the display.

### Slack Notification

When Slack MCP is detected (`integrations.slack.available: true`), the orchestrator sends notifications for:
- Pipeline start (with run ID and requirement summary)
- Stage transitions (batched, not per-stage — only IMPLEMENT, VERIFY, REVIEW, SHIP)
- Alerts requiring attention (with resolution link)
- Pipeline completion (with final score and PR link)

Slack notifications are best-effort. MCP failure degrades to file-only progress (no recovery engine involvement).

### Direct File Resolution

Users can resolve alerts by editing `alerts.json` directly:

```json
{
  "resolved": true,
  "resolution": "continue"
}
```

The orchestrator detects the change on its next poll cycle (30 seconds).

## Configuration

In `forge-config.md`:

    background:
      alert_timeout_minutes: 60
      poll_interval_seconds: 30
      slack_notifications: true
      progress_update_interval_seconds: 10

| Parameter | Valid Values | Default | Description |
|-----------|-------------|---------|-------------|
| `background.alert_timeout_minutes` | 10-360 | 60 | Minutes before unresolved alert triggers abort |
| `background.poll_interval_seconds` | 5-120 | 30 | How often orchestrator checks for alert resolution |
| `background.slack_notifications` | `true`, `false` | `true` | Send Slack notifications when MCP available |
| `background.progress_update_interval_seconds` | 5-60 | 10 | How often `status.json` is refreshed during long operations |

## Orchestrator Behavior

When `state.json.background: true`, the orchestrator modifies its behavior:

1. **No interactive UI**: `AskUserQuestion` calls are replaced by auto-resolution or alert escalation. `TaskCreate`/`TaskUpdate` calls are suppressed (progress tracked via files instead).
2. **Progress writes**: After every stage transition, agent dispatch, score change, or convergence iteration, the orchestrator updates `status.json` and appends to `timeline.jsonl`.
3. **Stage summaries**: After each stage completes, the orchestrator writes a summary to `stage-summary/{N}-{STAGE_NAME}.json`.
4. **Alert handling**: Safety escalations pause the pipeline and write to `alerts.json`. Non-safety decisions are auto-resolved.
5. **Completion**: On pipeline completion, the orchestrator writes the final `status.json` update, closes all timeline events, and optionally sends a Slack notification.

### State Schema Addition

The `background` field in `state.json`:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `background` | boolean | `false` | Whether the run is in background mode |
| `background_paused` | boolean | `false` | Whether the run is paused on an alert |
| `background_paused_at` | string or null | `null` | ISO 8601 timestamp when pause began |
| `background_alert_id` | string or null | `null` | ID of the alert blocking progress |

### Interaction with Other Modes

- **Sprint mode** (`--sprint --background`): Each feature run gets its own `progress/` directory under `.forge/runs/{id}/progress/`. The sprint orchestrator aggregates status across all runs.
- **Dry-run** (`--dry-run`): Overrides `--background`. No progress artifacts are created.
- **Resume** (`/forge-admin recover resume`): Works normally. If the previous run was background, resume also runs in background mode unless `--interactive` is passed.
