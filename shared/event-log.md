# Event Log

Unified append-only event log for pipeline observability, audit, and replay. All pipeline events flow through a single log file (`.forge/events.jsonl`) before being reflected in other artifacts. Subsumes `decisions.jsonl` and `progress/timeline.jsonl` as backward-compatible filtered views.

## File Location

`.forge/events.jsonl` -- append-only, one JSON object per line (JSON Lines format). Created on first event emission. Gitignored with the rest of `.forge/`.

**Sprint mode:** Per-run event files at `.forge/runs/{id}/events.jsonl` to avoid cross-run contention.

## Event Envelope

Every line in `events.jsonl` is a self-contained JSON object:

```json
{
  "id": 1,
  "ts": "2026-04-13T10:00:05.123Z",
  "type": "STAGE_TRANSITION",
  "run_id": "run-2026-04-13-abc123",
  "stage": "PREFLIGHT",
  "agent": "fg-100-orchestrator",
  "parent_id": null,
  "data": {}
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | integer | yes | Monotonically increasing sequence number within the run. Starts at 1. |
| `ts` | string (ISO 8601) | yes | Event timestamp with millisecond precision. |
| `type` | string (enum) | yes | Event type -- one of the 12 types below. |
| `run_id` | string | yes | Run identifier matching `state.json.run_id`. Links events to a specific pipeline execution. |
| `stage` | string | yes | Current pipeline stage at time of event. One of the 10 stage names or `PRE_PIPELINE`/`POST_PIPELINE`. |
| `agent` | string | yes | Agent that emitted the event (e.g., `fg-100-orchestrator`, `fg-300-implementer`). |
| `parent_id` | integer or null | yes | ID of the causally preceding event. `null` for root events (pipeline start). Enables causal chain traversal. |
| `data` | object | yes | Type-specific payload. Schema varies by event type -- see below. |

Full JSON Schema: `shared/schemas/event-schema.json`.

## Event Types (12)

### PIPELINE_START

Emitted once at the beginning of each run. Always has `parent_id: null`.

```json
{
  "type": "PIPELINE_START",
  "data": {
    "requirement": "Add user profile endpoint",
    "mode": "standard",
    "spec_file": ".forge/specs/user-profile.md",
    "background": false,
    "dry_run": false,
    "components": ["backend", "frontend"]
  }
}
```

### PIPELINE_END

Emitted once at run completion (success, abort, or failure).

```json
{
  "type": "PIPELINE_END",
  "data": {
    "outcome": "success",
    "final_score": 92,
    "total_iterations": 5,
    "duration_seconds": 840,
    "pr_url": "https://github.com/org/repo/pull/42"
  }
}
```

`outcome` values: `success`, `aborted`, `failed`, `dry_run_complete`.

### STAGE_TRANSITION

Emitted on every stage change.

```json
{
  "type": "STAGE_TRANSITION",
  "data": {
    "from_stage": "EXPLORING",
    "to_stage": "PLANNING",
    "reason": "Exploration complete, 42 files indexed"
  }
}
```

### AGENT_DISPATCH

Emitted when an agent is dispatched via the Agent tool.

```json
{
  "type": "AGENT_DISPATCH",
  "data": {
    "target_agent": "fg-300-implementer",
    "task_id": "FG-042",
    "model": "sonnet",
    "prompt_hash": "sha256:abc123",
    "prompt_tokens_estimate": 12000,
    "context_summary": "Implement UserController with 3 endpoints"
  }
}
```

### AGENT_COMPLETE

Emitted when a dispatched agent returns.

```json
{
  "type": "AGENT_COMPLETE",
  "data": {
    "target_agent": "fg-300-implementer",
    "task_id": "FG-042",
    "duration_seconds": 45,
    "tokens_in": 12000,
    "tokens_out": 3500,
    "model": "sonnet",
    "outcome": "success",
    "files_changed": ["src/main/kotlin/UserController.kt"],
    "findings_count": 0
  }
}
```

### FINDING

Emitted for every quality finding raised by a review agent.

```json
{
  "type": "FINDING",
  "data": {
    "category": "SEC-INJECTION",
    "severity": "CRITICAL",
    "confidence": "HIGH",
    "file": "src/main/kotlin/UserController.kt",
    "line": 42,
    "message": "Unsanitized user input in SQL query",
    "agent": "fg-411-security-reviewer",
    "dedup_key": "backend|src/main/kotlin/UserController.kt|42|SEC"
  }
}
```

### DECISION

Emitted for every branching decision. Replaces direct writes to `decisions.jsonl`. The data payload matches the existing decision log schema from `shared/decision-log.md`.

```json
{
  "type": "DECISION",
  "data": {
    "decision": "state_transition",
    "input": { "current_state": "IMPLEMENTING", "event": "verify_pass" },
    "choice": "VERIFYING",
    "alternatives": ["IMPLEMENTING (retry)"],
    "reason": "All tests pass, advancing to VERIFY stage",
    "confidence": "HIGH"
  }
}
```

### STATE_WRITE

Emitted for every `state.json` mutation via `forge-state-write.sh`.

```json
{
  "type": "STATE_WRITE",
  "data": {
    "field": "story_state",
    "old_value": "IMPLEMENTING",
    "new_value": "VERIFYING",
    "seq": 15
  }
}
```

### RECOVERY

Emitted when a recovery strategy is triggered.

```json
{
  "type": "RECOVERY",
  "data": {
    "error_type": "TEST_FAILURE",
    "strategy": "targeted_fix",
    "budget_before": 3.5,
    "budget_after": 2.5,
    "budget_cost": 1.0,
    "circuit_breaker_state": "CLOSED"
  }
}
```

### USER_INTERACTION

Emitted for every `AskUserQuestion` call and its response.

```json
{
  "type": "USER_INTERACTION",
  "data": {
    "question": "Score is 65 (CONCERNS). Options: continue, revert, abort",
    "options": ["continue", "revert", "abort"],
    "response": "continue",
    "response_time_seconds": 12
  }
}
```

### CONVERGENCE

Emitted for every convergence engine evaluation.

```json
{
  "type": "CONVERGENCE",
  "data": {
    "phase": "perfection",
    "state": "IMPROVING",
    "score": 88,
    "previous_score": 82,
    "delta": 6,
    "phase_iteration": 2,
    "total_iterations": 5,
    "action": "continue"
  }
}
```

### CHECKPOINT

Emitted when a checkpoint is created or restored.

```json
{
  "type": "CHECKPOINT",
  "data": {
    "action": "create",
    "checkpoint_file": ".forge/checkpoint-feat-user-profile.json",
    "task_id": "FG-042",
    "stage": "IMPLEMENTING"
  }
}
```

## Causal Chain Structure

The `parent_id` field enables causal chain traversal. Example chain:

```
id=1  PIPELINE_START (parent_id=null)
id=2  STAGE_TRANSITION to PREFLIGHT (parent_id=1)
id=5  STAGE_TRANSITION to IMPLEMENTING (parent_id=2)
id=6  AGENT_DISPATCH fg-300-implementer (parent_id=5)
id=7  AGENT_COMPLETE fg-300-implementer (parent_id=6)
id=8  STAGE_TRANSITION to VERIFYING (parent_id=7)
id=9  AGENT_DISPATCH fg-500-test-gate (parent_id=8)
id=10 FINDING TEST-FAIL (parent_id=9)
id=11 AGENT_COMPLETE fg-500-test-gate (parent_id=9)
id=12 DECISION convergence_evaluation IMPROVING (parent_id=11)
id=13 RECOVERY targeted_fix (parent_id=10)
```

### Parent ID Assignment Rules

- `PIPELINE_START` always has `parent_id: null`.
- `STAGE_TRANSITION` parent is the previous `STAGE_TRANSITION` or `PIPELINE_START`.
- `AGENT_DISPATCH` parent is the `STAGE_TRANSITION` that entered the current stage.
- `AGENT_COMPLETE` parent is the matching `AGENT_DISPATCH` (same `target_agent` + `task_id`).
- `FINDING` parent is the `AGENT_DISPATCH` that produced it.
- `DECISION` parent is the most recent `AGENT_COMPLETE` or `CONVERGENCE` event.
- `STATE_WRITE` parent is the `DECISION` or `STAGE_TRANSITION` that triggered it.
- `RECOVERY` parent is the `FINDING` or `AGENT_COMPLETE` that triggered recovery.
- `USER_INTERACTION` parent is the `DECISION` or `CONVERGENCE` that prompted the question.
- `CONVERGENCE` parent is the most recent `AGENT_COMPLETE` from a verify or review agent.
- `CHECKPOINT` parent is the `AGENT_COMPLETE` that preceded checkpoint creation.

## Backward Compatibility

When `events.backward_compat: true` (default):

1. **DECISION events** are also written to `.forge/decisions.jsonl` in the existing schema format (per `shared/decision-log.md`).
2. **All events in background mode** are also written to `.forge/progress/timeline.jsonl` in the existing timeline schema.

This ensures consumers of `decisions.jsonl` and `progress/timeline.jsonl` continue to work during the migration period. See the spec's migration path for deprecation timeline.

## Emission

Events are emitted via `shared/emit-event.sh`:

```bash
emit-event.sh <type> <stage> <agent> '<json_data>'
```

The script:
1. Auto-increments the `id` from the last line of `events.jsonl`.
2. Generates an ISO 8601 timestamp with millisecond precision.
3. Uses `mkdir`-based locking for thread-safe appends (no `flock` -- MacOS compatible).
4. Sources `platform.sh` for cross-platform helpers.
5. Exits silently (exit 0) if `.forge/` does not exist.

**Fire-and-forget** -- event emission MUST NOT block the pipeline. If the write fails, the pipeline continues without event logging.

## Replay Capability

`/forge-replay --from=<event-id>` reconstructs pipeline state at any point and resumes from there:

1. Read `events.jsonl` up to the specified event ID (inclusive).
2. Reconstruct `state.json` by replaying `STATE_WRITE` events in order.
3. Identify the stage and convergence phase at the target event.
4. Set `state.json._replaying = true` (prevents re-emission of replayed events).
5. Invoke orchestrator from the identified stage.
6. New events append with IDs continuing from the last event.

**Constraints:** Replay is valid only within the same run (`run_id`). Worktree state is not rolled back. `USER_INTERACTION` events require re-answering.

## Query Interface

`/forge-events` provides filtered event queries:

```bash
/forge-events                                      # All events, current run
/forge-events --stage=REVIEWING                    # Events from REVIEWING stage
/forge-events --type=FINDING                       # Only findings
/forge-events --type=FINDING --stage=REVIEWING     # Findings from REVIEWING
/forge-events --agent=fg-411-security-reviewer     # Events from security reviewer
/forge-events --chain=42                           # Causal chain from event 42
/forge-events --run=run-2026-04-12-abc123          # Events from a specific run
/forge-events --since=2026-04-13T10:00:00Z         # Events after timestamp
/forge-events --summary                            # Aggregate counts by type and stage
```

For `--chain`, follows `parent_id` links to build the causal tree from the specified event back to `PIPELINE_START`.

## Configuration

In `forge-config.md`:

```yaml
events:
  enabled: true                   # Master toggle (default: true)
  retention_days: 90              # Events older than this pruned on /forge-reset (default: 90)
  max_file_size_mb: 50            # Prune oldest events when file exceeds this (default: 50)
  replay_enabled: true            # Enable /forge-replay skill (default: true)
  emit_state_writes: true         # Emit STATE_WRITE events (verbose, default: true)
  backward_compat: true           # Also write to decisions.jsonl and progress/timeline.jsonl (default: true)
```

Constraints enforced at PREFLIGHT:
- `retention_days` must be >= 1 and <= 365.
- `max_file_size_mb` must be >= 10 and <= 200.

## Retention

- `events.jsonl` **survives `/forge-reset`** (same as `explore-cache.json`, `plan-cache/`, `wiki/`, `trust.json`).
- Events older than `events.retention_days` are pruned at PREFLIGHT.
- When file exceeds `events.max_file_size_mb`, oldest events are pruned until under the limit (oldest 25% per pass).
- Only manual `rm -rf .forge/` removes all events.

## File Locking

Uses `mkdir`-based atomic locking (NOT `flock`) for MacOS compatibility. Lock directory: `.forge/events.jsonl.lock`. Exponential backoff on contention (100ms, 200ms, 400ms). Leverages `acquire_lock_with_retry` from `shared/platform.sh`.

Sprint mode avoids contention entirely by using per-run event files at `.forge/runs/{id}/events.jsonl`.

## Integration Points

| System | Integration | Direction |
|--------|-------------|-----------|
| `forge-state-write.sh` | Emit STATE_WRITE events on every state mutation | Write |
| `forge-state.sh` | Emit STAGE_TRANSITION events on stage changes | Write |
| fg-100-orchestrator | Emit AGENT_DISPATCH/COMPLETE, PIPELINE_START/END | Write |
| fg-400-quality-gate | Emit FINDING events per finding | Write |
| fg-500-test-gate | Emit FINDING events for test failures | Write |
| Recovery engine | Emit RECOVERY events on strategy selection | Write |
| Convergence engine | Emit CONVERGENCE events on evaluation | Write |
| `decisions.jsonl` | Backward-compatible write from DECISION events | Write (compat) |
| `progress/timeline.jsonl` | Backward-compatible write in background mode | Write (compat) |
| `/forge-replay` | Read events, reconstruct state, re-run from point | Read |
| `/forge-events` | Read and query events | Read |
| `/forge-insights` | Read events for trend analysis across runs | Read |
| fg-700-retrospective | Read events for decision quality analysis | Read |

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Write failure (disk full, permissions) | Log ERROR. Pipeline continues without event logging. `state.json` writes unaffected. |
| Corrupt line (non-JSON) | On read: skip corrupt lines, log WARNING. On write: append from last valid line. |
| Sequence gap (id=5, id=7, missing id=6) | On read: log WARNING. On replay: skip gap, reconstruct from available events. |
| Replay target not found | Error: `REPLAY_EVENT_NOT_FOUND`. Display nearest available event IDs. |
| Replay from cross-run event | Error: `REPLAY_CROSS_RUN`. Replay only works within a single `run_id`. |
| File exceeds `max_file_size_mb` | At PREFLIGHT: prune oldest events. If still over, prune oldest 25%. Log INFO with count. |
| `events.enabled: false` | No events written. `/forge-replay` and `/forge-events` return informative error. |
| `backward_compat: false` | `decisions.jsonl` not written. Consumers must use `events.jsonl` with type filter. |

## Performance Characteristics

- **Write overhead**: ~2-5ms per event (one `jq` call + file append). Typical run emits 50-200 events. Total: 0.1-1.0 seconds across entire run.
- **File size**: ~300-500 bytes per event. 200-event run = ~100KB. At 3 runs/day for 90 days: ~27MB.
- **Read performance**: `jq` filtering over 50MB JSONL is ~2-3 seconds. Mid-run queries over <1MB are instant.
- **Replay overhead**: State reconstruction from STATE_WRITE events is O(n). For 200 events, <1 second.
- **No LLM cost**: All event operations are pure bash/jq.
