---
name: repair-state
description: Validate and repair .forge/state.json — fix corrupted counters, stale locks, invalid states, and WAL recovery. Confirms changes before writing.
---

# /repair-state — State Repair Tool

You validate `.forge/state.json` and fix specific issues found. Unlike `/forge-diagnose` (read-only) and `/forge-reset` (full wipe), this skill makes targeted repairs while preserving pipeline progress.

## Instructions

### 1. Pre-Checks

1. Check if `.forge/state.json` exists.
   - If not: report "No pipeline state found. Nothing to repair. Run `/forge-run` to start a pipeline." and stop.
2. Attempt to parse `.forge/state.json` as JSON.
   - If unparseable: attempt WAL recovery first (step 2). If WAL recovery fails, report "state.json is corrupted beyond repair. Run `/forge-reset` to start fresh." and stop.
3. Read `.claude/forge-config.md` for configured maximums (fallback to defaults).

### 2. WAL Recovery

Before any other repair, check for pending WAL entries:

```bash
bash shared/forge-state-write.sh recover --forge-dir .forge
```

- If recovery succeeds and state.json is now valid: report "Recovered state from write-ahead log." and continue with remaining checks.
- If recovery fails or no WAL exists: continue to next step.

### 3. Identify Repairs

Run each check below. Collect all needed repairs before applying any.

**R1: Schema version mismatch**
- If `version` is missing or not `"1.5.0"`: propose setting `version` to `"1.5.0"`.

**R2: Missing required fields**
- For each of `story_id`, `requirement`, `story_state`, `mode`, `complete`: if missing, propose a repair.
  - `story_id`: set to `"unknown-repair-{date}"` (e.g., `"unknown-repair-2026-04-10"`).
  - `requirement`: set to `"unknown (recovered by repair-state)"`.
  - `story_state`: infer from `stage_timestamps` (latest completed stage + 1). If no timestamps: set to `"PREFLIGHT"`.
  - `mode`: set to `"standard"`.
  - `complete`: set to `false`.

**R3: Invalid story_state**
- If `story_state` is not a recognized state (see `/forge-diagnose` for the full list): propose resetting to the last valid state inferred from `stage_timestamps`.

**R4: Invalid mode**
- If `mode` is not one of `standard`, `bugfix`, `migration`, `bootstrap`, `testing`, `refactor`, `performance`: propose setting to `"standard"`.

**R5: Corrupted sequence counter**
- If `_seq` is missing, zero, negative, or non-numeric: propose setting to `1`.

**R6: Counter overflows**
- Read maximums from `forge-config.md` or use defaults: `total_retries_max` = 10, `max_weight` = 5.5, `max_iterations` = 8.
- If `total_retries` > `total_retries_max`: propose capping to `total_retries_max`.
- If `recovery_budget.total_weight` > `recovery_budget.max_weight`: propose capping to `max_weight`.
- If `convergence.total_iterations` > configured `max_iterations`: propose capping to `max_iterations`.

**R7: Completion inconsistency**
- If `complete: true` but `story_state` is not `COMPLETE` or `ABORTED`: propose setting `story_state` to `"COMPLETE"`.
- If `complete: false` but `story_state` is `COMPLETE` or `ABORTED`: propose setting `complete` to `true`.

**R8: Stale lock file**
- If `.forge/.lock` exists:
  - Read PID from lock file.
  - Check if PID is still running: `kill -0 $pid 2>/dev/null`
  - If not running: propose removing `.forge/.lock`.
  - If no PID in lock file: propose removing `.forge/.lock`.

**R9: Missing convergence object**
- If `convergence` is missing entirely: propose initializing it with defaults:
  ```json
  {
    "phase": "correctness",
    "phase_iterations": 0,
    "total_iterations": 0,
    "plateau_count": 0,
    "last_score_delta": 0,
    "convergence_state": "IMPROVING",
    "phase_history": [],
    "safety_gate_passed": false,
    "safety_gate_failures": 0,
    "unfixable_findings": [],
    "diminishing_count": 0,
    "unfixable_info_count": 0
  }
  ```

**R10: Missing recovery_budget object**
- If `recovery_budget` is missing entirely: propose initializing it with defaults:
  ```json
  {
    "total_weight": 0.0,
    "max_weight": 5.5,
    "applications": []
  }
  ```

### 4. Present Repair Plan

If no repairs are needed: report "State is healthy. No repairs needed." and stop.

If repairs are needed, present them to the user:

Use `AskUserQuestion`:
- Header: "State Repair Plan"
- Question: "Found {n} issues in state.json. Apply these repairs?"
- List each repair with its description (e.g., "R6: Cap total_retries from 15 to 10")
- Options:
  - "Apply all" (description: "Fix all {n} issues")
  - "Cancel" (description: "Leave state unchanged")

### 5. Apply Repairs

If the user confirms:

1. Read current state.json content.
2. Apply all proposed mutations to the JSON object using `python3`:
   ```bash
   python3 -c "
   import json, sys
   state = json.load(open('.forge/state.json'))
   # ... apply mutations ...
   state['_seq'] = state.get('_seq', 0) + 1  # increment _seq for consistency
   print(json.dumps(state, indent=2))
   " > /tmp/forge-repair-state.json
   ```
3. Write the repaired state using `forge-state-write.sh` (preserves WAL and atomic write semantics):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/shared/forge-state-write.sh" write "$(cat /tmp/forge-repair-state.json)" --forge-dir .forge
   ```
   If `forge-state-write.sh` is not available, fall back to direct write with `mv`:
   ```bash
   mv /tmp/forge-repair-state.json .forge/state.json
   ```
4. If a stale lock was detected (R8): remove `.forge/.lock`.
5. Verify the repaired state.json is valid JSON by reading it back.
5. Report what was fixed:

```
## Repair Results

Applied {n} repairs to .forge/state.json:
- R{n}: {description} — FIXED
- ...

State file is now valid. Run `/forge-diagnose` to verify.
```

If the user cancels: report "Repair cancelled. State unchanged."

## Important

- NEVER delete `.forge/state.json` — that is what `/forge-reset` does.
- NEVER modify `.claude/forge.local.md`, `.claude/forge-config.md`, or `.claude/forge-log.md`.
- NEVER dispatch pipeline agents or trigger recovery.
- Always confirm repairs with the user before writing.
- Use `forge-state-write.sh recover` for WAL recovery — do not manually parse the WAL file.
- Back up the original state by reporting all changes so the user knows what was modified.
