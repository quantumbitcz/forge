# Phase 3: State Management Evolution

**Status:** Approved  
**Date:** 2026-04-15  
**Depends on:** Phase 1 (Python files extracted)  
**Unlocks:** Phase 4

## Problem

1. **No schema migration:** If a new field is added in v1.6.0, old v1.5.0 `state.json` files lack it. No `migrate_state()` function exists. Adding fields requires manual coordination.

2. **WAL race condition:** In `forge-state-write.sh` lines 236-242, the check-and-recover sequence is not atomic — another process can create `state.json` between the existence check and the recovery operation.

3. **state.json grows unbounded:** `score_history`, `convergence.phase_history`, and `recovery.applications` all append with no size limits. On long-running or multi-iteration projects, this can grow to megabytes.

4. **Checkpoint persistence undocumented:** `agent-communication.md` mentions checkpoints but the lifecycle (create, use, clean up) isn't specified anywhere.

## Solution

### 1. Create `shared/python/state_migrate.py`

**Interface:** Reads state JSON from stdin, writes migrated JSON to stdout.

```python
#!/usr/bin/env python3
"""State schema migration: applies sequential migrations to bring state.json up to date."""
import json, sys

CURRENT_VERSION = '1.6.0'

MIGRATIONS = {
    '1.5.0': migrate_1_5_0_to_1_6_0,
}

def migrate_1_5_0_to_1_6_0(state):
    """Add fields introduced in v1.6.0.
    
    This is the single migration for all Phase 1-6 changes.
    All new fields across all phases are added here to keep
    one migration per schema version.
    """
    import datetime
    
    # Circuit breaker tracking (Phase 4)
    recovery = state.setdefault('recovery', {})
    recovery.setdefault('circuit_breakers', {})
    
    # Flapping detection on circuit breakers (Phase 4)
    # Note: flapping_count and locked are per-circuit-breaker fields,
    # not top-level. They are added when a circuit breaker entry is created.
    
    # Planning critic counter (Phase 5)
    state.setdefault('critic_revisions', 0)
    
    # Schema migration history (capped at 20 entries)
    history = state.setdefault('schema_version_history', [])
    history.append({
        'from': '1.5.0',
        'to': '1.6.0',
        'timestamp': datetime.datetime.utcnow().isoformat() + 'Z'
    })
    if len(history) > 20:
        state['schema_version_history'] = history[-20:]
    
    state['version'] = '1.6.0'
    return state

def migrate(state):
    version = state.get('version', '1.5.0')
    while version != CURRENT_VERSION:
        if version not in MIGRATIONS:
            print(f"ERROR: No migration path from {version}", file=sys.stderr)
            sys.exit(2)
        state = MIGRATIONS[version](state)
        version = state['version']
    return state
```

**Exit codes:** 0 = success (migrated or already current), 1 = JSON parse error, 2 = no migration path.

### 2. Integrate migration into `forge-state.sh`

In the `do_read()` function (and at the start of `do_transition()`), after loading state.json:

```bash
# Migrate state schema if needed
local version
version=$(printf '%s' "$state" | "$PYTHON" -c "import json,sys; print(json.load(sys.stdin).get('version','1.5.0'))")
if [[ "$version" != "1.6.0" ]]; then
  state=$(printf '%s' "$state" | "$PYTHON" "$SCRIPT_DIR/python/state_migrate.py")
  if [[ $? -eq 0 ]]; then
    # Write back migrated state
    bash "$STATE_WRITER" write "$state" --forge-dir "$FORGE_DIR"
  fi
fi
```

Migration runs at most once per state file (subsequent reads see v1.6.0 and skip).

### 3. Fix WAL race condition

**File:** `shared/forge-state-write.sh` lines 236-242

Wrap the check-and-recover in the same flock that protects writes:

```bash
do_read() {
  local state_file="${FORGE_DIR:-.forge}/state.json"
  local wal_file="${FORGE_DIR:-.forge}/state.wal"
  local lock_file="${FORGE_DIR:-.forge}/.state.lock"
  
  # Atomic check-and-recover under lock
  if [[ ! -f "$state_file" ]] && [[ -f "$wal_file" ]]; then
    (
      if command -v flock &>/dev/null; then
        flock -w 5 200 || { echo '{}'; return; }
      else
        local lock_dir="${lock_file}.d"
        local attempts=0
        while ! mkdir "$lock_dir" 2>/dev/null; do
          attempts=$((attempts + 1))
          [[ $attempts -ge 50 ]] && { echo '{}'; return; }
          sleep 0.1
        done
        trap "rmdir '$lock_dir' 2>/dev/null" RETURN
      fi
      # Re-check under lock (another process may have recovered)
      if [[ ! -f "$state_file" ]] && [[ -f "$wal_file" ]]; then
        do_recover "$state_file" "$wal_file"
      fi
    ) 200>"$lock_file"
  fi
  
  if [[ -f "$state_file" ]]; then
    cat "$state_file"
  else
    echo '{}'
  fi
}
```

Key: the existence check is repeated inside the lock (double-check locking pattern).

### 4. Add state.json size caps

**File:** `shared/python/state_transitions.py` — add at the end, after applying counter/convergence changes:

```python
# Size caps — prevent unbounded growth
MAX_SCORE_HISTORY = 50
MAX_PHASE_HISTORY = 20
MAX_RECOVERY_APPLICATIONS = 30

if len(state.get('score_history', [])) > MAX_SCORE_HISTORY:
    state['score_history'] = state['score_history'][-MAX_SCORE_HISTORY:]

conv = state.get('convergence', {})
if len(conv.get('phase_history', [])) > MAX_PHASE_HISTORY:
    conv['phase_history'] = conv['phase_history'][-MAX_PHASE_HISTORY:]

recovery_budget = state.get('recovery_budget', {})
if len(recovery_budget.get('applications', [])) > MAX_RECOVERY_APPLICATIONS:
    recovery_budget['applications'] = recovery_budget['applications'][-MAX_RECOVERY_APPLICATIONS:]
```

These caps apply on every transition — O(1) check, no performance impact.

### 5. Document checkpoint persistence

**File:** `shared/state-schema.md` — add new section:

```markdown
## Checkpoint Persistence

Checkpoints enable mid-pipeline resume after interruption.

### Lifecycle

1. **Create:** The orchestrator creates a checkpoint after each task completes:
   - Location: `.forge/checkpoints/checkpoint-{storyId}-{taskId}.json`
   - Content: Current state.json snapshot + task-specific context (plan fragment, files changed)
   
2. **Read:** On resume (`/forge-resume`), the orchestrator:
   - Reads `.forge/state.json` to determine last stage
   - Loads the most recent checkpoint for context
   - Resumes from the checkpoint's task, not the beginning of the stage

3. **Clean up:** Checkpoints are deleted when:
   - Pipeline reaches COMPLETE state (all checkpoints for this story_id)
   - Pipeline reaches ABORTED state (all checkpoints for this story_id)
   - `/forge-reset` clears all `.forge/checkpoints/`
   - Note: both COMPLETE and ABORTED are terminal states that trigger cleanup

### Schema

```json
{
  "story_id": "FG-042",
  "task_id": "FG-042-3",
  "timestamp": "2026-04-15T10:30:00Z",
  "stage": "IMPLEMENTING",
  "state_snapshot": { ... },
  "context": {
    "plan_task_index": 2,
    "files_changed": ["src/auth/middleware.ts"],
    "test_status": "GREEN"
  }
}
```

### Survival Rules

- Checkpoints survive `/forge-resume` (that's their purpose)
- Checkpoints are cleared by `/forge-reset` and pipeline completion
- Checkpoints do NOT survive `rm -rf .forge/`
```

## Files Changed

| File | Action |
|------|--------|
| `shared/python/state_migrate.py` | **Create** — schema migration engine |
| `shared/forge-state.sh` | **Modify** — call migration before reads |
| `shared/forge-state-write.sh` | **Modify** — fix WAL race with double-check locking |
| `shared/python/state_transitions.py` | **Modify** — add size caps after transition application |
| `shared/state-schema.md` | **Modify** — add checkpoint persistence section, bump version to 1.6.0 |

## Testing

- Existing state tests (79+) must pass
- New tests:
  - `tests/unit/state-migration.bats`:
    - v1.5.0 state migrated to v1.6.0 has `recovery.circuit_breakers`, `critic_revisions`, `schema_version_history`
    - Already-v1.6.0 state passes through unchanged
    - Unknown version (e.g., "0.9.0") exits with code 2
  - `tests/unit/state-size-caps.bats`:
    - State with 100 score_history entries → capped to 50 after transition
    - State with 5 score_history entries → unchanged after transition
  - `tests/scenario/wal-race-recovery.bats`:
    - Simulate concurrent read during recovery (verify double-check locking)

## Risks

- **Migration on every read:** Checking version string adds one Python call per read. Mitigation: version check is a single `json.load` + string comparison — <5ms. Only runs migration when version differs.
- **Size cap data loss:** Capping `score_history` to 50 means older scores are lost. Mitigation: 50 is generous (typical runs have <20 iterations). `/forge-insights` can derive trends from the last 50.

## Success Criteria

1. State schema migration runs automatically and transparently
2. WAL recovery is atomic (no race between check and recover)
3. `score_history`, `phase_history`, and `recovery.applications` are bounded
4. Checkpoint persistence is documented with clear lifecycle
5. Version bumped to 1.6.0 in state-schema.md
