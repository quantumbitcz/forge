---
name: pipeline-status
description: Show current pipeline state, last run results, quality score, and Linear tracking status
disable-model-invocation: false
---

# Pipeline Status

Show the current state of the development pipeline for this project.

## What to do

1. Check if `.pipeline/state.json` exists
   - If not: report "No pipeline run in progress. Run `/pipeline-run` to start."

2. If it exists, read it and display:
   - **Current stage:** `story_state` value (e.g., IMPLEMENTING, REVIEWING)
   - **Story ID:** `story_id`
   - **Quality score:** last recorded score (if REVIEW stage reached)
   - **Fix cycles:** `verify_fix_count`, `quality_cycles`, `test_cycles`
   - **Stage timestamps:** which stages have completed and when
   - **Linear tracking:** Epic ID and status (if `linear.epic_id` is set)
   - **Integrations:** which MCPs were detected as available

3. Check for recent stage notes:
   - Read the latest `.pipeline/stage_*_notes_*.md` file
   - Show a 2-3 line summary of the last stage's output

4. If `complete: true` in state.json:
   - Report "Last run completed successfully"
   - Show final quality score and verdict
   - Show PR URL if available
