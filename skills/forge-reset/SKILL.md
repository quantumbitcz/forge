---
name: forge-reset
description: Clear pipeline run state and start fresh while preserving accumulated learnings
disable-model-invocation: false
---

# Pipeline Reset

Clear the pipeline run state so you can start fresh.

## What to do

1. Use `AskUserQuestion` to confirm with the user:
   - Header: "Pipeline Reset"
   - Question: "This will clear run state inside `.forge/` (state.json, checkpoints, stage notes, reports). Cross-run caches (explore-cache, plan-cache) are preserved. Learnings in `.claude/forge-log.md` are preserved."
   - Options: "Reset — clear run state and start fresh" / "Cancel — keep current state"

2. If confirmed:

   ## Concurrent Run Check

   Before cleanup, check for active pipeline runs:
   1. If `.forge/.lock` exists:
      - Read PID from `.forge/.lock` (if present)
      - Check if PID is still running (`kill -0 $pid 2>/dev/null`)
      - If running: warn user "A pipeline run appears to be active (PID {pid}). Resetting now may cause the active run to fail. Proceed anyway?" Use `AskUserQuestion` with options: "Force reset" / "Cancel"
      - If not running (stale lock): proceed — the lock is stale

   ## Graph Cleanup

   Before removing `.forge/`:
   1. If `.forge/docker-compose.neo4j.yml` exists:
      - Run `docker compose -f .forge/docker-compose.neo4j.yml down -v` to stop container and remove volume
      - This prevents orphaned Docker containers and volumes
      - **On failure:** Log warning "Docker cleanup failed: {error}. Orphaned containers may remain — run `docker ps -a` to check." Continue with reset — Docker failure should not block state cleanup.
   2. If `.forge/worktree` exists and is a git worktree:
      - Run `git worktree remove .forge/worktree --force` to cleanly remove the worktree
      - This prevents dangling worktree entries in `.git/worktrees/`
      - **On failure:** Log warning "Worktree cleanup failed: {error}. Run `git worktree list` to check for dangling entries and `git worktree prune` to clean up." Continue with reset.

   ## Cleanup (selective — preserves cross-run caches)

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
       # .forge/explore-cache.json — cross-run codebase index
       # .forge/plan-cache/ — cross-run plan cache
       # .forge/docs-index.json — documentation index
       # .forge/wiki/ — auto-generated wiki (v1.20)
       # .forge/agent-card.json — A2A agent card (v1.19)

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

## Important
- NEVER delete `.claude/forge-log.md` — this contains accumulated learnings across all runs
- NEVER delete `.claude/forge.local.md` — this is the project configuration
- NEVER delete `.claude/forge-config.md` — this contains auto-tuned runtime parameters
- ONLY delete `.forge/` which contains ephemeral run state
