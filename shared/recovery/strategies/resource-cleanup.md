---
name: resource-cleanup
description: Frees system resources (disk, memory, processes) and retries the failed action. Targets forge-managed caches and orphan processes only.
---

# Resource Cleanup Strategy

Handles failures caused by resource exhaustion: disk full, memory pressure, process limits, and token budget. Frees resources by cleaning forge-managed caches and killing orphan processes, then retries.

---

## 1. Disk Space (ENOSPC / No space left on device)

### 1.1 Assessment

Check current disk usage:

```bash
df -h .
du -sh .forge/ 2>/dev/null
du -sh build/ .gradle/ node_modules/.cache/ 2>/dev/null
```

### 1.2 Cleanup Targets (safe to delete)

Clean in this order, checking disk space after each step:

| Priority | Target | Command | Typical Savings |
|----------|--------|---------|-----------------|
| 1 | Old pipeline reports | `find .forge/reports/ -name "*.md" -mtime +7 -delete` | Small |
| 2 | Pipeline partial files | `rm -f .forge/partial-*.json` | Small |
| 3 | Corrupt state backups | `rm -f .forge/*.corrupt.*` | Small |
| 4 | Build caches | `rm -rf build/ .gradle/caches/ .gradle/build-cache/` | 100MB-1GB |
| 5 | Node cache | `rm -rf node_modules/.cache/` | 50-500MB |
| 6 | Kotlin incremental | `rm -rf build/kotlin/` | 50-200MB |
| 7 | Test reports (old) | `find . -path "*/build/reports" -type d -exec rm -rf {} +` | 10-100MB |

### 1.3 Never Delete

- Source code files
- `.forge/state.json` (current state)
- `.forge/checkpoint-*.json` (current checkpoints)
- `node_modules/` (dependencies, not cache)
- `.git/` contents
- User configuration files

### 1.4 After Cleanup

1. Verify space was freed: `df -h .`
2. If sufficient space recovered (>500MB free): retry the failed action, return `RECOVERED`.
3. If insufficient: return `ESCALATE` with disk usage report and suggestion to free space manually.

---

## 2. Memory / Token Budget

### 2.1 Agent Token Budget

When an agent approaches its context window limit:

1. **Reduce prompt size:**
   - Strip exploration results down to file paths only (remove content summaries).
   - Remove PREEMPT items with low relevance score.
   - Summarize previous stage notes instead of including full text.

2. **Split the task:**
   - If implementing, break remaining tasks into smaller sub-dispatches.
   - Each sub-dispatch gets only its own task context, not the full plan.

3. **Compact history:**
   - Write current state to stage notes file.
   - Suggest orchestrator run `/compact` to compress conversation.

### 2.2 Process Memory (OOM adjacent)

When the system is under memory pressure but not yet at OOM:

1. **Kill orphan processes (cross-platform):**

   On UNIX/macOS/Linux (use `pkill`):
   ```bash
   pkill -f "GradleDaemon" 2>/dev/null
   pkill -f "node.*--watch" 2>/dev/null
   pkill -f "kotlin-daemon" 2>/dev/null
   ```

   On Windows/WSL (use `taskkill` or PowerShell):
   ```powershell
   Get-Process | Where-Object { $_.CommandLine -match "GradleDaemon|node.*--watch|kotlin-daemon" } | Stop-Process -Force -ErrorAction SilentlyContinue
   ```

   **Detection:** Use `shared/platform.sh` `detect_os()` to determine the platform. On `windows`, prefer PowerShell. On `darwin`/`linux`, use `pkill`.

2. **Reduce parallelism:** Suggest orchestrator reduce `parallel_threshold` to 1 for remaining tasks.

3. **Retry** the failed action.

---

## 3. Process Limits (Too many open files / fork failed)

### 3.1 Open Files

```bash
# Check current limit
ulimit -n
# Check what's consuming file descriptors
lsof -p $$ 2>/dev/null | wc -l
```

**Recovery:**
1. Kill orphan processes (same as 2.2).
2. Close unused file descriptors (Gradle daemons hold many).
3. Retry.

### 3.2 Fork Limit

```bash
# Count current processes
ps aux | wc -l
```

**Recovery:**
1. Kill orphan build daemons and watchers.
2. If process count is still high: return `ESCALATE` — system-level issue.
3. Retry.

---

## 4. Retry After Cleanup

After freeing resources:

1. Wait 2 seconds for OS to reclaim resources.
2. Re-execute the failed action.
3. If success: return `RECOVERED`.
4. If same resource error: return `ESCALATE` with detailed resource report.
5. If different error: re-classify through recovery engine.

---

## 5. Git Conflict Recovery

When `GIT_CONFLICT` errors are classified by the recovery engine:

**Detection criteria:**
- `git status` shows "both modified", "both added", or "both deleted" entries
- `git merge --abort` or `git rebase --abort` available (mid-merge/rebase state)
- `.git/MERGE_HEAD` or `.git/REBASE_HEAD` exists

**Recovery actions (sequential):**

1. **Abort in-progress merge/rebase:**
   - If `.git/MERGE_HEAD` exists: `git merge --abort`
   - If `.git/REBASE_HEAD` exists: `git rebase --abort`
   - Verify clean state: `git status --porcelain` returns empty

2. **Worktree conflict (Stage 4/8):**
   - If conflict is in `.forge/worktree`: remove and recreate worktree
   - Re-run from the conflicting stage with fresh worktree
   - Log: "Worktree conflict recovered by recreating worktree"

3. **Base branch divergence (Stage 8):**
   - If base branch moved ahead: attempt `git rebase` onto latest base
   - On rebase conflict: escalate to user with file list
   - Log conflict details for manual resolution

**Escalation:** If all recovery attempts fail, escalate to user with:
> "Git conflict unresolvable by recovery engine. Conflicting files: {file_list}. Options: (1) Resolve manually, (2) Recreate worktree from scratch, (3) Abort pipeline."

**Weight:** 0.5 (same as other resource-cleanup operations)

---

## 6. Output

Return to recovery engine:

```json
{
  "result": "RECOVERED | ESCALATE",
  "details": "What was cleaned and how much was freed",
  "resources_freed": {
    "disk_mb": 450,
    "processes_killed": 3,
    "caches_cleared": ["build/", ".gradle/caches/"]
  },
  "current_resources": {
    "disk_free_mb": 2048,
    "process_count": 142
  }
}
```
