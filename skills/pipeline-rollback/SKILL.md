---
name: pipeline-rollback
description: Safely rollback pipeline changes — revert worktree, restore state, or undo specific commits
disable-model-invocation: false
---

# Pipeline Rollback

Safely undo pipeline changes when something goes wrong.

## What to do

Ask the user which type of rollback they need, then execute:

### Precondition Detection

Before presenting rollback options, detect the current state:

1. Check if `.pipeline/worktree` exists → Mode 1 available (pre-merge rollback)
2. Check if `.pipeline/state.json` exists and `complete: true` → Mode 2 available (post-merge revert)
3. Check git log for pipeline merge commits → Mode 2 available
4. Only present modes that are actually available based on detection

### Mode 1: Rollback Worktree (most common)

If the pipeline's worktree has unwanted changes:

**Option A — Delete the worktree entirely (main tree unaffected):**

    git worktree remove .pipeline/worktree --force

**Option B — Reset worktree to a specific commit:**

    cd .pipeline/worktree
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

    /pipeline-reset

This removes `.pipeline/` (state, checkpoints, notes) but preserves code changes and learnings.

## Important
- ALWAYS confirm with the user before executing destructive operations
- NEVER force-delete without showing what will be removed first
- Show `git log --oneline -5` before any git reset/revert so the user can verify
- If unsure which mode the user needs, ask
