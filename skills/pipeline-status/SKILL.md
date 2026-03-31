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
   - **Mode:** `mode` (standard/migration/bootstrap). Note if `dry_run: true`.
   - **Quality score:** last recorded score (if REVIEW stage reached)
   - **Convergence:** `convergence.phase` (correctness/perfection/safety_gate), `convergence.convergence_state` (IMPROVING/PLATEAUED/REGRESSING), `convergence.total_iterations`, `convergence.safety_gate_failures`. If `convergence.unfixable_findings` is non-empty, show count.
   - **Fix cycles:** `verify_fix_count`, `quality_cycles`, `test_cycles`
   - **Stage timestamps:** which stages have completed and when
   - **Linear tracking:** Epic ID and status (if `linear.epic_id` is set)
   - **Linear sync:** `linear_sync.in_sync` (true/false, note failed operations if not in sync)
   - **Integrations:** which MCPs were detected as available
   - **Total retries:** `total_retries` / `total_retries_max` (global retry budget usage)
   - **Score history:** `score_history` (quality oscillation trend, e.g., `[85, 78, 92]`)
   - **Recovery budget:** `recovery_budget.total_weight` / `recovery_budget.max_weight` (recovery budget usage)
   - **Documentation:** `documentation.files_discovered` files, `documentation.decisions_extracted` decisions, `documentation.stale_sections` stale sections (if documentation subsystem active)

3. Check for recent stage notes:
   - Read the latest `.pipeline/stage_*_notes_*.md` file
   - Show a 2-3 line summary of the last stage's output

4. If `complete: true` in state.json:
   - If `abort_reason` is present and non-empty: report "Last run aborted: {abort_reason}"
   - Otherwise: report "Last run completed successfully"
   - Show final quality score and verdict
   - Show PR URL if available
   - If `recovery_failed: true`: report "Recovery engine failed at stage {last_known_stage}"
