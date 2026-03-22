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
   - `verify_fix_count`: Sum `fix_attempts` across all `tasks_completed` in checkpoint files.
   - `test_cycles`: Count `stage_5_notes` sections containing "Test cycle" or "test fix".
   - `quality_cycles`: Count `stage_6_notes` sections containing "Quality cycle" or "review cycle".
   - `validation_retries`: Count `stage_3_notes` sections containing "REVISE".
   - `total_retries`: Sum of all above counters.
   - Fallback: If any counter is undeterminable from available evidence, use the **configured maximum** (conservative). This prevents extra retries beyond limits.
   - `complete`: false.
   - `last_commit_sha`: from `git log -1 --format=%H`.

5. **Log all reconstructed counter values** with their sources (e.g., `"verify_fix_count=3 (from 3 checkpoint fix_attempts)"`, `"test_cycles=2 (from stage_5_notes)"`, `"quality_cycles=MAX(3) (undeterminable, using configured maximum)"`).
6. **Write reconstructed state** and log: `"State reconstructed from {sources used}. Counters reconstructed from evidence or set to configured maximum."`

### Post-Reconstruction Schema Validation

After writing the reconstructed `state.json`, verify the `version` field:

1. If `version` is missing or < `"1.3"`: apply the appropriate migration chain (1.1→1.2→1.3)
2. If `version` is `"1.3"`: no migration needed
3. Log: "Reconstructed state at schema version {version}. Migration applied: {yes/no}."

This ensures reconstructed state files always match the current schema, regardless of what artifacts were used for reconstruction.

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

### 1.3a Checkpoint Corruption Recovery

When checkpoint JSON is unreadable (partial write, truncated, corrupted):

1. **Try JSON repair:** Trim to last complete `}` bracket, attempt re-parse
2. **Try fallback checkpoints:** If multiple `checkpoint-*.json` files exist, use the most recent valid one
3. **Parse stage notes:** If no valid checkpoint exists, reconstruct `tasks_completed[]` from `stage_4_notes_{storyId}.md` by scanning for "Task completed" or "T00N: pass/fail" entries
4. **Git-based reconstruction:** `git log --oneline` in the worktree to find pipeline commits per task
5. **Last resort:** If all reconstruction fails, treat ALL tasks as remaining. The pipeline will re-run completed tasks (idempotent if code already exists) rather than skip them incorrectly.

For counter reconstruction when checkpoint is lost, use the **evidence-based approach** (see counter reconstruction above). If evidence is ambiguous, prefer the lower estimate to allow legitimate retries rather than blocking them.

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
- **Conservative counter reconstruction.** Reconstruct counters from checkpoint and stage notes evidence. When a counter is undeterminable, use the configured maximum — this prevents extra retries beyond limits rather than allowing unbounded retries.
- **Prefer reconstruction over fresh start.** A reconstructed state that resumes mid-pipeline saves more work than starting over.

---

## 4. Output

Return to recovery engine:

```json
{
  "result": "RECOVERED | ESCALATE",
  "details": "Description of what was reconstructed and from what sources",
  "reconstruction_sources": ["checkpoint", "git_log", "stage_notes", "filesystem"],
  "data_loss_risk": "none | counter_approximated | unknown_drift",
  "user_action_required": false,
  "corrupt_files_preserved": [".pipeline/state.json.corrupt.20260322T143000"]
}
```
