---
name: pipeline-reset
description: Clear pipeline run state and start fresh while preserving accumulated learnings
disable-model-invocation: false
---

# Pipeline Reset

Clear the pipeline run state so you can start fresh.

## What to do

1. Confirm with user: "This will remove the `.pipeline/` directory (run state, checkpoints, stage notes). Learnings in `.claude/pipeline-log.md` are preserved. Proceed? (y/n)"

2. If confirmed:
   - Remove `.pipeline/` directory: `rm -rf .pipeline/`
   - Report what was cleaned: state.json, checkpoint files, stage notes, reports
   - Confirm: "Pipeline state cleared. Learnings preserved in `.claude/pipeline-log.md`. Ready for a fresh run with `/pipeline-run`."

3. If not confirmed:
   - "Reset cancelled. Pipeline state preserved."

## Important
- NEVER delete `.claude/pipeline-log.md` — this contains accumulated learnings across all runs
- NEVER delete `.claude/dev-pipeline.local.md` — this is the project configuration
- ONLY delete `.pipeline/` which contains ephemeral run state
