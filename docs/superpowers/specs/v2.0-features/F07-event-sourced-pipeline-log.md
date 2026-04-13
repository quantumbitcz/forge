# F07: Event-Sourced Pipeline Log with Replay

## Status
DRAFT -- 2026-04-13

## Problem Statement

Forge's pipeline state is currently fragmented across multiple artifacts:

- **`state.json`** -- mutable root state, overwritten on each stage transition via `forge-state-write.sh` (WAL + `_seq` versioning). Captures current state but not history.
- **`decisions.jsonl`** -- append-only branching decisions per `shared/decision-log.md`. Covers 12 required decision types but not operational events (agent dispatches, findings, state writes).
- **`progress/timeline.jsonl`** -- background-mode event log with 12 event types (`pipeline_start`, `stage_enter`, `agent_dispatch`, etc.). Only written when `--background` is active. Not available in interactive runs.
- **`stage_N_notes_*.md`** -- prose-form stage summaries. Not machine-parseable.
- **`checkpoint-{storyId}.json`** -- per-task snapshots for recovery. Point-in-time, not a continuous log.

This fragmentation creates three concrete problems:

1. **No replay**: When a pipeline fails at iteration 14, there is no way to reconstruct the state at iteration 7 and re-run from there. Checkpoints help but only capture per-task snapshots, not the full timeline.
2. **Incomplete audit trail**: Interactive runs have no `timeline.jsonl`. The decision log captures branching decisions but misses operational events. Debugging requires correlating multiple files manually.
3. **No causal chain**: When a finding in REVIEW leads to a fix in IMPLEMENT that breaks a test in VERIFY, there is no link between these events. Root cause analysis requires manual reconstruction.

OpenHands' event-sourced architecture demonstrates that a unified event log enables deterministic replay and dramatically simplifies debugging. SWE-Agent's trajectory logging shows the value of capturing complete agent interaction history for analysis.

## Proposed Solution

Introduce a single append-only event log (`.forge/events.jsonl`) that captures ALL pipeline events with causal linking. Subsume `decisions.jsonl` and `progress/timeline.jsonl` as filtered views of this log. Add replay capability via `/forge-replay` that reconstructs state at any point and re-runs from there.

## Detailed Design

### Architecture

The event log is a write-ahead log that sits below all existing state management. Every state mutation, agent dispatch, finding, and decision flows through the event log before being reflected in `state.json` or other artifacts.

```
[Orchestrator / Agents]
        |
        v
  Event Emitter (forge-events.sh)
        |
        +---> .forge/events.jsonl  (append-only, source of truth)
        |
        +---> forge-state-write.sh  (state.json mutation, existing)
        |
        +---> decisions.jsonl       (filtered view, backward compat)
        |
        +---> progress/timeline.jsonl  (filtered view, background mode)
```

#### Component Ownership

| Component | Owner | Description |
|-----------|-------|-------------|
| `forge-events.sh` | New shared script | Event emission, ID generation, append logic |
| Event schema | `shared/event-schema.md` | New shared doc defining all event types |
| Replay engine | `forge-replay.sh` | New shared script for state reconstruction |
| `/forge-replay` skill | New skill | User-facing replay command |
| `/forge-events` skill | New skill | User-facing event query command |

### Schema / Data Model

#### Event Envelope Schema

Every event in `.forge/events.jsonl` is a single JSON line conforming to this envelope:

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
| `type` | string (enum) | yes | Event type -- see Event Types table. |
| `run_id` | string | yes | Run identifier matching `state.json.run_id`. Links events to a specific pipeline execution. |
| `stage` | string | yes | Current pipeline stage at time of event. One of the 10 stage names or `PRE_PIPELINE`/`POST_PIPELINE`. |
| `agent` | string | yes | Agent that emitted the event (e.g., `fg-100-orchestrator`, `fg-300-implementer`). |
| `parent_id` | integer or null | yes | ID of the causally preceding event. `null` for root events (pipeline start). Enables causal chain traversal. |
| `data` | object | yes | Type-specific payload. Schema varies by event type -- see below. |

#### Event Types and Data Schemas

##### PIPELINE_START
Emitted once at the beginning of each run.

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

##### PIPELINE_END
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

| `outcome` values | Meaning |
|------------------|---------|
| `success` | Pipeline completed and shipped |
| `aborted` | User or system aborted |
| `failed` | Unrecoverable error |
| `dry_run_complete` | Dry-run finished at VALIDATE |

##### STAGE_TRANSITION
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

##### AGENT_DISPATCH
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

##### AGENT_COMPLETE
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

##### FINDING
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

##### DECISION
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

##### STATE_WRITE
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

##### RECOVERY
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

##### USER_INTERACTION
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

##### CONVERGENCE
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

##### CHECKPOINT
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

##### CONDENSATION
Reserved for F08 (Context Condensation). Emitted when context is condensed during a convergence loop.

```json
{
  "type": "CONDENSATION",
  "data": {
    "iteration": 5,
    "tokens_before": 95000,
    "tokens_after": 42000,
    "tokens_saved": 53000,
    "retained_tags": ["active_findings", "test_failures", "acceptance_criteria"]
  }
}
```

#### Causal Chain Structure

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

To trace why a recovery was triggered: follow `parent_id` from event 13 back to event 10 (the failing finding), then to event 9 (the test gate dispatch), then to event 8 (the VERIFY stage entry).

**Parent ID assignment rules:**
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

### Configuration

In `forge-config.md`:

```yaml
events:
  enabled: true                   # Master toggle (default: true)
  retention_days: 90              # Events older than this are pruned on /forge-reset (default: 90)
  max_file_size_mb: 50            # Prune oldest events when file exceeds this size (default: 50)
  replay_enabled: true            # Enable /forge-replay skill (default: true)
  emit_state_writes: true         # Emit STATE_WRITE events (verbose, default: true)
  backward_compat: true           # Also write to decisions.jsonl and progress/timeline.jsonl (default: true)
```

Constraints enforced at PREFLIGHT:
- `retention_days` must be >= 1 and <= 365.
- `max_file_size_mb` must be >= 10 and <= 200.

### Data Flow

#### Write Path

The event emitter (`forge-events.sh`) is a bash function sourced by `forge-state.sh` and invoked by the orchestrator and agents:

```bash
# forge-events.sh
emit_event() {
  local type="$1"
  local data="$2"
  local parent_id="${3:-null}"

  local seq
  seq=$(_next_event_seq)

  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

  local run_id
  run_id=$(_read_state_field "run_id")

  local stage
  stage=$(_read_state_field "story_state")

  local agent
  agent=$(_current_agent)

  local event
  event=$(jq -n \
    --argjson id "$seq" \
    --arg ts "$ts" \
    --arg type "$type" \
    --arg run_id "$run_id" \
    --arg stage "$stage" \
    --arg agent "$agent" \
    --argjson parent_id "$parent_id" \
    --argjson data "$data" \
    '{id: $id, ts: $ts, type: $type, run_id: $run_id, stage: $stage, agent: $agent, parent_id: $parent_id, data: $data}')

  echo "$event" >> "$FORGE_DIR/events.jsonl"

  # Backward compatibility: also write to legacy files
  if [[ "$type" == "DECISION" ]] && _config_bool "events.backward_compat" true; then
    _write_decision_legacy "$event"
  fi
  if _config_bool "events.backward_compat" true && _state_bool "background"; then
    _write_timeline_legacy "$event"
  fi

  echo "$seq"  # Return the event ID for parent_id chaining
}
```

**Sequence number management:** `_next_event_seq` reads the last line of `events.jsonl`, extracts the `id` field, and increments. On empty file, starts at 1. File locking via `mkdir`-based atomic lock prevents concurrent write races (same mechanism as existing hooks system). On Linux, `flock` is used when available for higher throughput.

#### Integration with Existing Write Paths

1. **`forge-state-write.sh`**: After writing to `state.json`, calls `emit_event "STATE_WRITE" "$delta"` where `$delta` is the JSON diff.
2. **`forge-state.sh` transitions**: After each state transition, calls `emit_event "STAGE_TRANSITION" "$transition_data"`.
3. **Orchestrator agent dispatches**: Before calling the Agent tool, emits `AGENT_DISPATCH`. After agent returns, emits `AGENT_COMPLETE`.
4. **Quality gate**: For each finding, emits `FINDING` event.
5. **Recovery engine**: On strategy selection, emits `RECOVERY` event.
6. **Convergence engine**: On evaluation, emits `CONVERGENCE` event.

#### Replay Algorithm

`/forge-replay --from=<event-id>` reconstructs state and re-runs:

```
FUNCTION replay(from_event_id):
  1. Read events.jsonl up to from_event_id (inclusive)
  2. Reconstruct state.json by replaying STATE_WRITE events in order:
     - Start from initial state (PIPELINE_START data)
     - Apply each STATE_WRITE delta sequentially
     - Result: state.json as it was at from_event_id
  3. Write reconstructed state to .forge/state.json
  4. Identify the stage and convergence phase at from_event_id
  5. Set state.json._replaying = true (prevents re-emission of replay events)
  6. Invoke orchestrator with --from={stage} flag
  7. After orchestrator starts, set _replaying = false
  8. New events append to events.jsonl with IDs continuing from last event
```

**Replay constraints:**
- Replay is only valid within the same run (same `run_id`). Cross-run replay is not supported (file system state may differ).
- Replay from a `USER_INTERACTION` event requires the user to re-answer the question (non-deterministic).
- Replay does not re-execute completed agent work. It restores state and continues from the specified point.
- The worktree state is NOT rolled back. Replay assumes worktree files are still present. If they were cleaned up, the replay will fail with `REPLAY_WORKTREE_MISSING`.

#### Query Interface

`/forge-events` provides filtered event queries:

```bash
/forge-events                                          # All events, current run
/forge-events --stage=REVIEWING                        # Events from REVIEWING stage
/forge-events --type=FINDING                           # Only findings
/forge-events --type=FINDING --stage=REVIEWING         # Findings from REVIEWING
/forge-events --agent=fg-411-security-reviewer         # Events from security reviewer
/forge-events --chain=42                               # Causal chain starting from event 42
/forge-events --run=run-2026-04-12-abc123              # Events from a specific run
/forge-events --since=2026-04-13T10:00:00Z             # Events after timestamp
/forge-events --summary                                # Aggregate counts by type and stage
```

The skill reads `events.jsonl`, applies filters, and formats output. For `--chain`, it follows `parent_id` links to build the causal tree.

### Integration Points

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
| `progress/timeline.jsonl` | Backward-compatible write from all events in background mode | Write (compat) |
| `/forge-replay` | Read events, reconstruct state, re-run from point | Read |
| `/forge-events` | Read and query events | Read |
| `/forge-insights` | Read events for trend analysis across runs | Read |
| fg-700-retrospective | Read events for decision quality analysis | Read |

### Error Handling

| Scenario | Behavior |
|----------|----------|
| `events.jsonl` write failure (disk full, permissions) | Log ERROR. Pipeline continues without event logging. Existing `state.json` writes are not affected. |
| `events.jsonl` is corrupt (non-JSON line) | On read: skip corrupt lines, log WARNING per corrupt line. On write: append continues from last valid line. |
| Sequence gap (events.jsonl has id=5, id=7, missing id=6) | On read: log WARNING. On replay: skip gap, reconstruct from available events. |
| Replay target event not found | Error: `REPLAY_EVENT_NOT_FOUND`. Display nearest available event IDs. |
| Replay from cross-run event | Error: `REPLAY_CROSS_RUN`. Replay only works within a single run. |
| File exceeds `max_file_size_mb` | At PREFLIGHT: prune events older than the oldest active run. If still over limit, prune oldest 25% of events. Log INFO with pruned count. |
| Concurrent writes (sprint mode) | `mkdir`-based lock on `events.jsonl` ensures atomic appends. Sprint runs with separate `runs/{id}/events.jsonl` files avoid contention entirely. |
| `backward_compat: false` and consumer reads `decisions.jsonl` | `decisions.jsonl` will be empty. Consumers must check `events.jsonl` with type filter. Log WARNING on first access to empty `decisions.jsonl`. |

## Performance Characteristics

- **Write overhead**: One `echo >> file` per event plus `jq` for JSON construction. Estimated 2-5ms per event. A typical pipeline run emits 50-200 events. Total write overhead: 0.1-1.0 seconds across the entire run.
- **File size**: Each event is approximately 300-500 bytes. A 200-event run produces ~100KB. At 3 runs/day for 90 days, the file reaches ~27MB -- well within the 50MB default limit.
- **Read performance**: `jq` filtering over 50MB JSONL is ~2-3 seconds. For real-time queries during a run, the file is typically <1MB.
- **Replay overhead**: State reconstruction from STATE_WRITE events is O(n) where n is the number of events up to the replay point. For a 200-event run, this is <1 second.
- **No LLM cost**: Event emission and querying are pure bash/jq operations. Replay invokes the orchestrator which has its normal LLM costs.

## Testing Approach

### Structural Tests

1. `forge-events.sh` exists, is executable, and has bash 4+ shebang.
2. Event type enum matches the documented types.
3. Backward compatibility: DECISION events produce valid `decisions.jsonl` entries.

### Unit Tests

1. **Event emission**: Emit 10 events, verify sequential IDs, valid JSON, correct timestamps.
2. **Parent ID assignment**: Emit a chain of STAGE_TRANSITION -> AGENT_DISPATCH -> FINDING -> RECOVERY. Verify parent_id links form the expected chain.
3. **Sequence recovery**: Given an `events.jsonl` with last id=42, emit a new event, verify id=43.
4. **Pruning**: Given a file at 51MB, verify pruning removes oldest events and file is under 50MB.
5. **Concurrent writes**: Two parallel processes emit events simultaneously via `mkdir`-based lock. Verify no data corruption and all events present.

### Contract Tests

1. STATE_WRITE events emitted by `forge-state-write.sh` are valid against the STATE_WRITE schema.
2. DECISION events emitted by the orchestrator match the `decisions.jsonl` schema from `shared/decision-log.md`.
3. Backward-compat `decisions.jsonl` entries are identical to direct writes.

### Scenario Tests

1. **Full run capture**: Execute a dry-run pipeline. Verify events.jsonl contains PIPELINE_START, STAGE_TRANSITION (for each stage), and PIPELINE_END.
2. **Causal chain**: Execute a run that triggers recovery. Verify the chain from FINDING to RECOVERY to AGENT_DISPATCH is correctly linked.
3. **Replay**: Execute a run, replay from mid-IMPLEMENT event, verify state is correctly reconstructed and pipeline continues.
4. **Query**: Execute a run, query events by stage and type, verify correct filtering.

## Acceptance Criteria

- [AC-001] GIVEN a pipeline run completes WHEN events are enabled (default) THEN `.forge/events.jsonl` contains at minimum PIPELINE_START, one STAGE_TRANSITION per stage visited, and PIPELINE_END, each with sequential `id` values and valid `parent_id` chains.
- [AC-002] GIVEN a DECISION event is emitted WHEN `backward_compat: true` (default) THEN the same decision also appears in `.forge/decisions.jsonl` in the existing schema format.
- [AC-003] GIVEN a background-mode run WHEN `backward_compat: true` THEN `progress/timeline.jsonl` is populated from event log data and matches the existing timeline schema.
- [AC-004] GIVEN a pipeline run that reached REVIEWING with event id=50 WHEN `/forge-replay --from=50` is invoked THEN `state.json` is reconstructed to its state at event 50 and the pipeline resumes from the REVIEWING stage.
- [AC-005] GIVEN `/forge-events --type=FINDING --stage=REVIEWING` is invoked THEN only FINDING events from the REVIEWING stage are returned.
- [AC-006] GIVEN `/forge-events --chain=42` is invoked THEN the complete causal chain from event 42 back to PIPELINE_START is returned in reverse chronological order.
- [AC-007] GIVEN `events.jsonl` exceeds `max_file_size_mb` WHEN a new pipeline run starts at PREFLIGHT THEN the oldest events are pruned until the file is under the limit, and an INFO log is emitted with the pruned event count.
- [AC-008] GIVEN `events.enabled: false` WHEN a pipeline run executes THEN no `events.jsonl` file is created or written to, and existing event-dependent features (`/forge-replay`, `/forge-events`) return an informative error.

## Migration Path

1. **v2.0.0**: Ship with `events.enabled: true` by default. `decisions.jsonl` and `progress/timeline.jsonl` continue to be written via backward compatibility. No consumer changes required.
2. **v2.0.x**: Migrate `/forge-insights` and `fg-700-retrospective` to read from `events.jsonl` instead of `decisions.jsonl` and `progress/timeline.jsonl`. Backward-compat writes continue.
3. **v2.1.0**: Deprecate direct reads from `decisions.jsonl` and `progress/timeline.jsonl`. Add deprecation warnings. Consider defaulting `backward_compat: false`.
4. **v2.2.0**: Remove backward-compat writes. `decisions.jsonl` and `progress/timeline.jsonl` no longer created.

## Dependencies

| Dependency | Type | Required? |
|------------|------|-----------|
| `forge-state-write.sh` modification | Shared script | Yes |
| `forge-state.sh` modification | Shared script | Yes |
| `forge-events.sh` (new) | New shared script | Yes |
| `/forge-replay` (new skill) | New skill | Yes |
| `/forge-events` (new skill) | New skill | Yes |
| fg-100-orchestrator event emission | Agent modification | Yes |
| fg-400-quality-gate event emission | Agent modification | Yes |
| fg-500-test-gate event emission | Agent modification | Yes |
| Recovery engine event emission | Shared infrastructure | Yes |
| Convergence engine event emission | Shared infrastructure | Yes |
| `jq` availability | External tool | Yes (already required by forge) |
| File locking mechanism | External tool | Uses `mkdir`-based atomic locking (same as existing hooks system) — no `flock` dependency. Fallback: `flock` on Linux where available for higher throughput. |
| Sprint mode: per-run event files | Architecture decision | No (enhancement) |
