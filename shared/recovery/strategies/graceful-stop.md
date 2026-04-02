---
name: graceful-stop
description: Performs a clean pipeline shutdown when recovery is not possible. Saves all state, checkpoints, and partial work. Provides a clear resume path.
---

# Graceful Stop Strategy

Handles unrecoverable failures by performing an orderly shutdown. Preserves all progress, commits partial work, and provides the user with a clear picture of what happened and how to resume.

---

## 1. Trigger Conditions

Graceful stop is invoked when:

- All recovery attempts for a failure category have been exhausted.
- The failure is classified as UNRECOVERABLE.
- User configuration is fundamentally broken.
- Required credentials are missing or expired.
- Filesystem permissions prevent pipeline operation.

---

## 2. Shutdown Sequence

Execute these steps in order. Each step is designed to be safe even if previous steps partially failed.

### 2.1 Save Pipeline State

1. **Update `state.json`:**
   - Set `story_state` to current stage value.
   - Set `complete` to `false`.
   - Add current timestamp to `stage_timestamps`.
   - Update all counters to their current values.
   - Add the triggering failure to `recovery.failures` array.

2. **Write checkpoint:**
   - Save `.forge/checkpoint-{storyId}.json` with current task progress.
   - Include `tasks_completed`, `tasks_remaining`, `tasks_failed` lists.

3. **Write stage notes:**
   - Save `.forge/stage_{N}_notes_{storyId}.md` for the current stage with:
     - What was in progress when the stop occurred.
     - Error details.
     - Partial results available.

### 2.2 Preserve Partial Work

1. **Check for uncommitted changes:**
   ```bash
   git status --porcelain
   ```

2. **If changes exist, commit to a temporary branch:**
   ```bash
   # Create WIP branch from current state
   git checkout -b wip/pipeline-{storyId}-{timestamp}
   git add -A
   git commit -m "wip: pipeline partial work before graceful stop

   Stage: {current_stage}
   Failure: {failure_category} — {failure_summary}
   Tasks completed: {N}/{total}

   Resume with: /forge-run --from={current_stage_name} {original_requirement}"

   # Return to original branch
   git checkout -
   ```

3. **If git operations fail** (e.g., merge conflicts): stash instead:
   ```bash
   git stash push -m "pipeline-recovery: partial work from {storyId}"
   ```

### 2.3 Clean Exit

1. **Remove lock files** if any exist:
   ```bash
   rm -f .forge/.lock
   ```

2. **Ensure state files are written** (not in a half-written state).

---

## 3. User Report

Generate a structured report for the user:

```
Pipeline stopped: UNRECOVERABLE failure

## What completed
- [Stage]: [status] — [brief result]
  (for each completed stage)

## What was in progress
- Stage: [current stage name]
- Task: [current task description]
- Progress: [N/M tasks completed in this stage]

## What caused the stop
- Category: [failure category]
- Error: [error summary]
- Recovery attempts: [N] — [brief description of each attempt]

## Partial work preserved
- Branch: wip/pipeline-{storyId}-{timestamp}
  (or: Stash: pipeline-recovery: partial work from {storyId})
- State: .forge/state.json (recovery-aware)
- Checkpoint: .forge/checkpoint-{storyId}.json

## How to resume
1. Fix the underlying issue: [specific suggestion based on failure]
2. Run: /forge-run --from={stage} {requirement}
   The pipeline will pick up from the last checkpoint.

## Alternative: Start fresh
1. Delete .forge/ directory
2. Run: /forge-run {requirement}
```

---

## 4. Exit Code

Always exit with code 0. The graceful stop itself is a success — it preserved state correctly. The failure is recorded in state.json, not in the exit code.

---

## 5. Output

Return to recovery engine:

```json
{
  "result": "ESCALATE",
  "details": "Graceful stop completed. State preserved.",
  "wip_branch": "wip/pipeline-{storyId}-{timestamp}",
  "resume_command": "/forge-run --from={stage} {requirement}",
  "completed_stages": ["PREFLIGHT", "EXPLORE", "PLAN"],
  "failed_stage": "IMPLEMENT",
  "tasks_completed": 3,
  "tasks_total": 7
}
```
