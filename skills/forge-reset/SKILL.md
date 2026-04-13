---
name: forge-reset
description: "Clear pipeline run state and start fresh while preserving accumulated learnings and cross-run caches. Use when you want to abandon the current run completely, when state is too corrupted for /repair-state, or before starting a clean pipeline run."
disable-model-invocation: false
---

# /forge-reset -- Pipeline Reset

Clear the pipeline run state so you can start fresh.

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. **State exists:** Check `.forge/` directory exists. If not: report "No pipeline state to reset. The `.forge/` directory does not exist." and STOP.

## Instructions

1. Use `AskUserQuestion` to confirm with the user:
   - Header: "Pipeline Reset"
   - Question: "This will clear run state inside `.forge/` (state.json, checkpoints, stage notes, reports). Cross-run caches (explore-cache, plan-cache) are preserved. Learnings in `.claude/forge-log.md` are preserved."
   - Options: "Reset -- clear run state and start fresh" / "Cancel -- keep current state"

2. If confirmed:

   ### Concurrent Run Check

   Before cleanup, check for active pipeline runs:
   1. If `.forge/.lock` exists:
      - Read PID from `.forge/.lock` (if present)
      - Check if PID is still running (`kill -0 $pid 2>/dev/null`)
      - If running: warn user "A pipeline run appears to be active (PID {pid}). Resetting now may cause the active run to fail. Proceed anyway?" Use `AskUserQuestion` with options: "Force reset" / "Cancel"
      - If not running (stale lock): proceed -- the lock is stale

   ### Graph Cleanup

   Before removing `.forge/`:
   1. If `.forge/docker-compose.neo4j.yml` exists:
      - Run `docker compose -f .forge/docker-compose.neo4j.yml down -v` to stop container and remove volume
      - This prevents orphaned Docker containers and volumes
      - **On failure:** Log warning "Docker cleanup failed: {error}. Orphaned containers may remain -- run `docker ps -a` to check." Continue with reset -- Docker failure should not block state cleanup.
   2. If `.forge/worktree` exists and is a git worktree:
      - Run `git worktree remove .forge/worktree --force` to cleanly remove the worktree
      - This prevents dangling worktree entries in `.git/worktrees/`
      - **On failure:** Log warning "Worktree cleanup failed: {error}. Run `git worktree list` to check for dangling entries and `git worktree prune` to clean up." Continue with reset.

   ### Cleanup (selective -- preserves cross-run caches)

   Remove run state files but preserve cross-run caches:

       # Remove run state
       rm -f .forge/state.json
       rm -f .forge/checkpoint-*.json
       rm -f .forge/stage_*_notes_*.md
       rm -f .forge/stage_final_notes_*.md
       rm -f .forge/.lock
       rm -f .forge/.check-engine-skipped
       rm -rf .forge/reports/
       rm -rf .forge/feedback/
       rm -rf .forge/tracking/
       rm -rf .forge/progress/
       rm -f .forge/evidence.json
       rm -f .forge/decisions.jsonl
       rm -f .forge/automation-log.jsonl

       # Preserve (do NOT delete):
       # .forge/explore-cache.json -- cross-run codebase index
       # .forge/plan-cache/ -- cross-run plan cache
       # .forge/docs-index.json -- documentation index
       # .forge/wiki/ -- auto-generated wiki (v1.20)
       # .forge/agent-card.json -- A2A agent card (v1.19)

   For full wipe including caches, manually run: `rm -rf .forge/`

   - Report what was cleaned: state.json, checkpoint files, stage notes, reports
   - If any cleanup warnings occurred, include them in the report
   - Confirm: "Pipeline state cleared. Learnings preserved in `.claude/forge-log.md`. Ready for a fresh run with `/forge-run`."

3. If not confirmed:
   - "Reset cancelled. Pipeline state preserved."

## What gets deleted

Deletes: state.json, checkpoint-*.json, stage_*_notes_*.md, stage_final_notes_*.md, .lock, .check-engine-skipped, reports/, feedback/, tracking/, progress/, evidence.json, decisions.jsonl

Preserves (inside .forge/): explore-cache.json, plan-cache/, docs-index.json, wiki/, agent-card.json

Does NOT touch (outside .forge/): forge-log.md, forge.local.md, forge-config.md

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| Active pipeline detected (live PID) | Warn user and require explicit "Force reset" confirmation |
| Docker cleanup fails | Log warning, continue with reset -- Docker failure is non-blocking |
| Worktree removal fails | Log warning, suggest `git worktree prune`, continue with reset |
| File deletion fails (permissions) | Report which files could not be deleted and suggest manual cleanup |
| State corruption | Reset handles corrupt state -- that is one of its primary use cases |

## Important

- NEVER delete `.claude/forge-log.md` -- this contains accumulated learnings across all runs
- NEVER delete `.claude/forge.local.md` -- this is the project configuration
- NEVER delete `.claude/forge-config.md` -- this contains auto-tuned runtime parameters
- ONLY delete `.forge/` which contains ephemeral run state

## See Also

- `/forge-abort` -- Stop an active pipeline gracefully while preserving state for resume (less destructive)
- `/forge-resume` -- Resume an aborted pipeline from its last checkpoint
- `/repair-state` -- Fix specific state.json issues without wiping everything
- `/forge-diagnose` -- Read-only diagnostic to understand what went wrong before deciding to reset
