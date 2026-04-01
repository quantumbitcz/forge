---
name: pipeline-reset
description: Clear pipeline run state and start fresh while preserving accumulated learnings
disable-model-invocation: false
---

# Pipeline Reset

Clear the pipeline run state so you can start fresh.

## What to do

1. Use `AskUserQuestion` to confirm with the user:
   - Header: "Pipeline Reset"
   - Question: "This will remove the `.pipeline/` directory (run state, checkpoints, stage notes). Learnings in `.claude/pipeline-log.md` are preserved."
   - Options: "Reset — remove .pipeline/ and start fresh" / "Cancel — keep current state"

2. If confirmed:

   ## Concurrent Run Check

   Before cleanup, check for active pipeline runs:
   1. If `.pipeline/.lock` exists:
      - Read PID from `.pipeline/.lock` (if present)
      - Check if PID is still running (`kill -0 $pid 2>/dev/null`)
      - If running: warn user "A pipeline run appears to be active (PID {pid}). Resetting now may cause the active run to fail. Proceed anyway?" Use `AskUserQuestion` with options: "Force reset" / "Cancel"
      - If not running (stale lock): proceed — the lock is stale

   ## Graph Cleanup

   Before removing `.pipeline/`:
   1. If `.pipeline/docker-compose.neo4j.yml` exists:
      - Run `docker compose -f .pipeline/docker-compose.neo4j.yml down -v` to stop container and remove volume
      - This prevents orphaned Docker containers and volumes
      - **On failure:** Log warning "Docker cleanup failed: {error}. Orphaned containers may remain — run `docker ps -a` to check." Continue with reset — Docker failure should not block state cleanup.
   2. If `.pipeline/worktree` exists and is a git worktree:
      - Run `git worktree remove .pipeline/worktree --force` to cleanly remove the worktree
      - This prevents dangling worktree entries in `.git/worktrees/`
      - **On failure:** Log warning "Worktree cleanup failed: {error}. Run `git worktree list` to check for dangling entries and `git worktree prune` to clean up." Continue with reset.

   - Remove `.pipeline/` directory: `rm -rf .pipeline/`
   - Report what was cleaned: state.json, checkpoint files, stage notes, reports
   - If any cleanup warnings occurred, include them in the report
   - Confirm: "Pipeline state cleared. Learnings preserved in `.claude/pipeline-log.md`. Ready for a fresh run with `/pipeline-run`."

3. If not confirmed:
   - "Reset cancelled. Pipeline state preserved."

## What gets deleted

Deletes: state.json, checkpoint-*.json, stage_*_notes_*.md, stage_final_notes_*.md, .lock, .check-engine-skipped, reports/, feedback/ (but NOT pipeline-log.md, pipeline-config.md, or dev-pipeline.local.md — these survive resets)

Note: `rm -rf .pipeline/` deletes ALL files under `.pipeline/` including `.pipeline/.lock` (concurrent run lock) and `.pipeline/.check-engine-skipped` (inline check skip counter). These are ephemeral files that should not survive a reset.

## Important
- NEVER delete `.claude/pipeline-log.md` — this contains accumulated learnings across all runs
- NEVER delete `.claude/dev-pipeline.local.md` — this is the project configuration
- NEVER delete `.claude/pipeline-config.md` — this contains auto-tuned runtime parameters
- ONLY delete `.pipeline/` which contains ephemeral run state
