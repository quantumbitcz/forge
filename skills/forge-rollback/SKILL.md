---
name: forge-rollback
description: "Safely rollback pipeline changes -- revert worktree, restore state, or undo specific commits. Use when a pipeline run produced unwanted changes, a merge introduced regressions, or you need to undo Linear ticket updates."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent']
disable-model-invocation: false
---

# /forge-rollback -- Pipeline Rollback

Safely undo pipeline changes when something goes wrong.

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. **Rollback target exists:** At least one of the following must be true:
   - `.forge/worktree` exists (Mode 1 available)
   - `.forge/state.json` exists with `complete: true` (Mode 2 available)
   - Recent pipeline merge commits exist in git log (Mode 2 available)
   If none: report "No pipeline changes to rollback. No worktree, no completed runs." and STOP.

## Instructions

Ask the user which type of rollback they need, then execute:

### Precondition Detection

Before presenting rollback options, detect the current state:

1. **Check for uncommitted changes**: Run `git status --porcelain`. If there are uncommitted changes, warn:
   "Warning: You have uncommitted changes. Rollback operations (especially `git reset --hard` or `git revert`) may affect your working tree. Consider committing or stashing first."
2. Check if `.forge/worktree` exists -> Mode 1 available (pre-merge rollback)
3. Check if `.forge/state.json` exists and `complete: true` -> Mode 2 available (post-merge revert)
4. Check git log for pipeline merge commits -> Mode 2 available
5. Only present modes that are actually available based on detection

### Mode 1: Rollback Worktree (most common)

If the pipeline's worktree has unwanted changes:

**Option A -- Delete the worktree entirely (main tree unaffected):**

    git worktree remove .forge/worktree --force

**Option B -- Reset worktree to a specific commit:**

    cd .forge/worktree
    git log --oneline -10   # show recent commits
    git reset --hard {commit-sha}

The main working tree is NEVER affected by worktree rollback.

### Mode 2: Rollback After Merge

If the worktree branch was already merged to your branch:

    # Find the merge commit
    git log --oneline -10

    # Revert the merge (creates a new commit that undoes the changes)
    git revert {merge-commit-sha}

### Mode 3: Rollback Linear Tickets

If Linear tickets were created but the pipeline failed:

- The pipeline does NOT auto-delete Linear tickets on failure
- Options:
  1. Archive the Epic in Linear (preserves history)
  2. Delete the Epic (if it was just a test run)
  3. Leave as-is (the tickets document the attempted work)

### Mode 4: Rollback State Only

If you want to keep code changes but reset pipeline state:

    /forge-reset

This removes `.forge/` (state, checkpoints, notes) but preserves code changes and learnings.

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| Worktree removal fails | Report error, suggest `git worktree prune` to clean up dangling entries |
| Git revert fails (merge conflicts) | Report the conflict and suggest manual resolution |
| User provides invalid commit SHA | Report "Commit not found" and re-prompt |
| Linear API unavailable | Report that Linear tickets cannot be modified. Suggest manual cleanup in the Linear UI |
| State corruption | Use `/forge-reset` (Mode 4) which handles corrupt state |

## Important

- ALWAYS confirm with the user before executing destructive operations
- NEVER force-delete without showing what will be removed first
- Show `git log --oneline -5` before any git reset/revert so the user can verify
- If unsure which mode the user needs, ask

## See Also

- `/forge-reset` -- Clear pipeline state without reverting code changes
- `/forge-abort` -- Stop an active pipeline before it produces changes to rollback
- `/forge-resume` -- Resume a pipeline instead of rolling back
- `/forge-status` -- Check current pipeline state before deciding to rollback
