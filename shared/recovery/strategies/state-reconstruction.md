---
name: state-reconstruction
description: Reconstructs or repairs corrupted pipeline state from checkpoints, git history, and filesystem evidence. Never silently discards changes.
---

# State Reconstruction Strategy

Handles missing, corrupted, or inconsistent pipeline state files. Reconstructs state from available evidence: checkpoints, git log, filesystem, and stage notes. Never silently discards data.

---

## 1. Failure Scenarios and Remediation

### 1.1 Missing `state.json`

The `.pipeline/state.json` file does not exist when it should (mid-pipeline run).

**Reconstruction steps:**

1. **Check for checkpoints:** Look for `.pipeline/checkpoint-*.json` files. If found, the most recent one contains task-level progress.
2. **Check for stage notes:** Look for `.pipeline/stage_*_notes_*.md` files. The highest stage number indicates the last completed stage.
3. **Check git log:** Look for pipeline commits:
   ```bash
   git log --oneline --grep="wip: pipeline" --grep="feat:" --grep="fix:" -20
   ```
   Pipeline checkpoint commits (`wip: pipeline checkpoint pre-implement`) indicate the stage reached.
4. **Reconstruct state.json:**
   - `story_id`: extract from checkpoint filename or stage notes filename.
   - `story_state`: derive from highest completed stage.
   - `stage_timestamps`: approximate from file modification times.
   - `verify_fix_count`, `quality_cycles`, `test_cycles`: set to 0 (conservative — may cause extra cycles but won't skip needed ones).
   - `complete`: false.
   - `last_commit_sha`: from `git log -1 --format=%H`.

5. **Write reconstructed state** and log: `"State reconstructed from {sources used}. Counters reset to 0 (conservative)."`

### 1.2 Invalid JSON in `state.json`

The file exists but contains invalid JSON (parse error).

**Remediation steps:**

1. **Preserve the corrupt file:** Copy to `.pipeline/state.json.corrupt.{timestamp}` for debugging.
2. **Attempt JSON repair:**
   - Check for trailing comma (common): remove it and re-parse.
   - Check for truncation (incomplete write): if the file ends mid-value, trim to last complete object.
   - Check for encoding issues: ensure UTF-8.
3. **If repair succeeds:** validate the repaired JSON against the state schema. If valid, use it.
4. **If repair fails:** fall back to reconstruction from checkpoints and git log (same as 1.1).

### 1.3 Invalid Checkpoint JSON

A `.pipeline/checkpoint-*.json` file contains invalid JSON.

**Remediation steps:**

1. **Preserve corrupt file** as `.corrupt.{timestamp}`.
2. **Check for other checkpoints:** If multiple checkpoint files exist, use the most recent valid one.
3. **If no valid checkpoints:** reconstruct task progress from:
   - `git diff` to see what files were changed.
   - Stage notes to see what was planned vs completed.
   - Filesystem: check if planned output files exist.

### 1.4 Git Drift

The filesystem state has diverged from what `state.json` or the checkpoint expects (e.g., user manually edited files, or a different tool made changes).

**Detection:**

```bash
git diff --name-only {last_commit_sha}
```

If this shows changes not tracked in the checkpoint's `files_modified` list, drift has occurred.

**Remediation:**

1. **Catalog the drift:** List files changed outside the pipeline's knowledge.
2. **Classify changes:**
   - Files the pipeline was going to modify anyway → likely safe to incorporate.
   - Files the pipeline has already modified → potential conflict.
   - New files not in the plan → user addition, preserve.
3. **Ask the user:** Present the drift summary and ask:
   ```
   Pipeline detected changes not tracked in state:
   - Modified: [file list]
   - New: [file list]

   Options:
   1. Incorporate these changes (pipeline continues with current filesystem state)
   2. Discard these changes (git checkout to last pipeline checkpoint)
   3. Pause for manual review
   ```
4. **Never silently discard.** If the user cannot be prompted (non-interactive), choose option 1 (incorporate) and log a warning.

### 1.5 State/Checkpoint Disagreement

`state.json` says the pipeline is in stage X, but the checkpoint says tasks from stage Y are complete (where X != Y).

**Remediation:**

1. **Trust the more detailed source:** Checkpoints are written per-task and are more granular.
2. **Update state.json** to reflect the checkpoint's progress.
3. **Log the inconsistency** for retrospective analysis.

---

## 2. Validation After Reconstruction

After any reconstruction or repair:

1. **Validate schema:** Ensure all required fields exist with valid types.
2. **Validate references:** For each file referenced in checkpoint `tasks_completed`, verify it exists on disk.
3. **Validate stage order:** Ensure `story_state` is consistent with completed stages.
4. **Write validation result** to the recovery log.

---

## 3. Safety Rules

- **Never silently discard changes.** If data cannot be reconstructed, escalate to the user.
- **Preserve corrupt files.** Always copy before overwriting for post-mortem analysis.
- **Conservative counter reset.** When counters cannot be determined, reset to 0. This may cause extra retry cycles but will never skip needed retries.
- **Prefer reconstruction over fresh start.** A reconstructed state that resumes mid-pipeline saves more work than starting over.

---

## 4. Output

Return to recovery engine:

```json
{
  "result": "RECOVERED | ESCALATE",
  "details": "Description of what was reconstructed and from what sources",
  "reconstruction_sources": ["checkpoint", "git_log", "stage_notes", "filesystem"],
  "data_loss_risk": "none | counter_reset | unknown_drift",
  "user_action_required": false,
  "corrupt_files_preserved": [".pipeline/state.json.corrupt.20260322T143000"]
}
```
