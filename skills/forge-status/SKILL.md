---
name: forge-status
description: "Show current pipeline run state (stage, score, convergence phase, integrations). Supports --watch for background run polling. For cross-run trends use /forge-history."
disable-model-invocation: false
---

# Pipeline Status

Show the current state of the development pipeline for this project.

## What to do

1. Check if `.forge/state.json` exists
   - If not: report "No pipeline run in progress. Run `/forge-run` to start."

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
   - Read the latest `.forge/stage_*_notes_*.md` file
   - Show a 2-3 line summary of the last stage's output

4. **Background run detection** — check if `.forge/progress/status.json` exists (indicates `--background` mode, see `shared/background-execution.md`):

   a. Read `.forge/progress/status.json` and display:
      - **Run ID:** `run_id`
      - **Current stage:** `stage` (e.g., IMPLEMENTING, REVIEWING) with `stage_number`/9
      - **Progress:** `progress_pct`% — render a visual progress bar (e.g. `[████████░░░░░░░░] 52%`)
      - **Quality score:** `score` (or "Not yet scored" if `null`)
      - **Convergence:** `convergence_phase` (`correctness`/`perfection`/`null`) — iteration `convergence_iteration`
      - **ETA:** `eta_minutes` minutes remaining (or "Calculating..." if `null`)
      - **Elapsed:** computed from `started_at` to `last_update`
      - **Model usage:** for each key in `model_usage`, show model name, dispatch count, tokens in/out (formatted as `45K in / 12K out`)

   b. **Alerts** — if `alerts` array is non-empty:
      - Display each alert with type, severity, message, and timestamp
      - If alert has `options`, show available resolution choices
      - If pipeline is paused (`state.json.background_paused: true`), show "PAUSED — awaiting resolution for alert `{background_alert_id}`" with the paused duration (from `background_paused_at` to now)
      - Explain how to resolve: edit `.forge/progress/alerts.json`, set `resolved: true` and `resolution` to the chosen option ID

   c. **Stage summaries** — read `.forge/progress/stage-summary/*.json` for completed stages and show:
      - Stage name, duration, agents dispatched count
      - Score delta (`score_before` → `score_after`) if available
      - Finding counts (CRITICAL/WARNING/INFO)

   d. **Timeline tail** — read the last 5 entries from `.forge/progress/timeline.jsonl` and display a compact event log

5. **`--watch` flag** — when invoked as `/forge-status --watch`:
   - Poll `.forge/progress/status.json` every 5 seconds (default, matches `background.progress_update_interval_seconds`)
   - Refresh the display with updated stage, progress, score, alerts, and model usage
   - Exit automatically when the pipeline completes (`stage` = `LEARNING` and `progress_pct` = 100) or aborts
   - If an alert appears during watch, highlight it immediately and show resolution instructions

6. If `complete: true` in state.json:
   - If `abort_reason` is present and non-empty: report "Last run aborted: {abort_reason}"
   - Otherwise: report "Last run completed successfully"
   - Show final quality score and verdict
   - Show PR URL if available
   - If `recovery_failed: true`: report "Recovery engine failed at stage {last_known_stage}"
