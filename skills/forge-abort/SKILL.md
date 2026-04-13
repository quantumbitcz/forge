---
name: forge-abort
description: "Stop an active pipeline run gracefully. Use when you want to pause work, need to change approach mid-pipeline, or want to interrupt a long-running run. Preserves state for /forge-resume. Safer than /forge-reset which clears all state."
allowed-tools: ['Read', 'Bash', 'AskUserQuestion']
---

## Prerequisites
1. Check `.forge/state.json` exists. If not: "No active pipeline to abort." STOP.
2. Read `story_state` from state.json. If `COMPLETE` or `ABORTED`: "Pipeline already finished (state: {story_state})." STOP.

## Instructions

1. **Read current state:** `story_state`, `convergence.phase`, `total_iterations`
2. **Confirm with user via AskUserQuestion:**
   "Pipeline is at stage {story_state}, iteration {total_iterations}. How would you like to proceed?"
   - Option 1: "Abort and preserve state for resume"
   - Option 2: "Abort and reset (equivalent to /forge-reset)"
   - Option 3: "Cancel — keep running"
3. **If option 1 (preserve):**
   a. Transition to ABORTED via the state machine:
      `bash shared/forge-state.sh transition user_abort_direct --forge-dir .forge`
   b. Release `.forge/.lock` if held: `rm -f .forge/.lock`
   c. Do NOT delete worktree (preserves work for resume)
   d. Report: "Pipeline aborted at {stage}. State preserved. Run /forge-resume to continue."
4. **If option 2 (reset):** Delegate to `/forge-reset`
5. **If option 3 (cancel):** "Abort cancelled. Pipeline continues."

**Important:** Never write directly to state.json. Always use `forge-state.sh transition` to maintain state machine integrity.

## Post-Abort State
- `story_state: ABORTED`
- `previous_state`: preserved for /forge-resume
- All counters preserved
- Worktree preserved
- Lock released

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| state.json missing | Report "No active pipeline to abort." and STOP |
| Pipeline already finished | Report "Pipeline already finished (state: {story_state})." and STOP |
| State transition fails | Report "Could not transition to ABORTED state. State machine error: {error}." Suggest `/repair-state` |
| Lock file removal fails | Log WARNING. Lock file will be detected as stale on next run |
| state.json write fails | Report error. State may be partially updated. Suggest `/repair-state` |
| State corruption | Attempt abort anyway via state machine. If that fails, suggest `/forge-reset` |

## See Also

- `/forge-resume` -- Resume the aborted pipeline from where it stopped
- `/forge-reset` -- Clear all state (more destructive -- use when resume is not needed)
- `/forge-status` -- Check pipeline state before deciding to abort
- `/forge-rollback` -- Rollback code changes made before the abort
