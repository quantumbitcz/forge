---
name: forge-abort
description: "Stop an active pipeline run gracefully. Preserves state for /forge-resume. Safer than /forge-reset which clears all state."
allowed-tools: ['Read', 'Bash', 'AskUserQuestion']
---

## Prerequisites
1. Check `.forge/state.json` exists. If not: "No active pipeline to abort." STOP.
2. Read `story_state` from state.json. If `COMPLETE` or `ABORTED`: "Pipeline already finished (state: {story_state})." STOP.

## Abort Procedure

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
