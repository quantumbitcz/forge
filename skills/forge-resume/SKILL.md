---
name: forge-resume
description: "Resume a previously aborted or failed pipeline run from its last checkpoint. Repairs state if needed, then continues from the last successful stage."
allowed-tools: ['Read', 'Write', 'Bash', 'Agent', 'AskUserQuestion', 'TaskCreate', 'TaskUpdate']
---

## Prerequisites
1. Check `.forge/state.json` exists. If not: "No pipeline state found. Run /forge-run to start a new pipeline." STOP.
2. Read `story_state`. Must be `ABORTED` or `ESCALATED`. If `COMPLETE`: "Pipeline already completed. Run /forge-run for a new pipeline." If other state: "Pipeline appears to be running (state: {story_state}). Use /forge-abort first."

## Resume Procedure

1. **State health check:** Run the same checks as `/repair-state`:
   a. Validate JSON structure
   b. Check counter consistency
   c. Verify `_seq` field
   d. If state is corrupted: attempt WAL recovery, report result

2. **Determine resume point:**
   a. Read `previous_state` field from state.json (set by the state machine during ABORTED/ESCALATED transition — contains the state the pipeline was in before abort)
   b. If `previous_state` is empty, fall back to last successful checkpoint from `stage_timestamps`
   c. Resume stage = the stage corresponding to `previous_state` or last successful checkpoint

3. **Present resume plan to user:**
   "Pipeline was at {previous_state}. Resume options:
   (1) Continue from {previous_state} (recommended)
   (2) Go back to PLANNING (re-plan with current context)
   (3) Start fresh (/forge-reset + /forge-run)"

4. **Resume execution:**
   a. Set `story_state` to chosen resume point
   b. Release ABORTED/ESCALATED status
   c. Dispatch orchestrator with `--from={resume_stage}`
   d. All existing counters, scores, and findings are preserved

## Edge Cases
- If worktree was deleted between abort and resume: re-create worktree from branch
- If branch was deleted: "Cannot resume -- branch {branch_name} no longer exists. Start fresh."
- If state.json was manually edited: validate with schema before resuming
