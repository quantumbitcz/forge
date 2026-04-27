---
name: forge-status
description: "[read-only] Show current pipeline run state -- stage, score, convergence phase, integrations, and background run progress. Use when you want to check what stage the pipeline is at, monitor a background run, or see the outcome of the last completed run."
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']
disable-model-invocation: false
---

# /forge-status -- Pipeline Status

Show the current state of the development pipeline for this project.

## Flags

- **--help**: print usage and exit 0
- **--json**: structured JSON output

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. **State exists:** Check `.forge/state.json` exists. If not: report "No pipeline run in progress. Run `/forge-run` to start." and STOP.

## Instructions

1. Read `.forge/state.json` and display:
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

2. Check for recent stage notes:
   - Read the latest `.forge/stage_*_notes_*.md` file
   - Show a 2-3 line summary of the last stage's output

3. **Background run detection** -- check if `.forge/progress/status.json` exists (indicates `--background` mode, see `shared/background-execution.md`):

   a. Read `.forge/progress/status.json` and display:
      - **Run ID:** `run_id`
      - **Current stage:** `stage` (e.g., IMPLEMENTING, REVIEWING) with `stage_number`/9
      - **Progress:** `progress_pct`% -- render a visual progress bar (e.g. `[████████░░░░░░░░] 52%`)
      - **Quality score:** `score` (or "Not yet scored" if `null`)
      - **Convergence:** `convergence_phase` (`correctness`/`perfection`/`null`) -- iteration `convergence_iteration`
      - **ETA:** `eta_minutes` minutes remaining (or "Calculating..." if `null`)
      - **Elapsed:** computed from `started_at` to `last_update`
      - **Model usage:** for each key in `model_usage`, show model name, dispatch count, tokens in/out (formatted as `45K in / 12K out`)

   b. **Alerts** -- if `alerts` array is non-empty:
      - Display each alert with type, severity, message, and timestamp
      - If alert has `options`, show available resolution choices
      - If pipeline is paused (`state.json.background_paused: true`), show "PAUSED -- awaiting resolution for alert `{background_alert_id}`" with the paused duration (from `background_paused_at` to now)
      - Explain how to resolve: edit `.forge/progress/alerts.json`, set `resolved: true` and `resolution` to the chosen option ID

   c. **Stage summaries** -- read `.forge/progress/stage-summary/*.json` for completed stages and show:
      - Stage name, duration, agents dispatched count
      - Score delta (`score_before` -> `score_after`) if available
      - Finding counts (CRITICAL/WARNING/INFO)

   d. **Timeline tail** -- read the last 5 entries from `.forge/progress/timeline.jsonl` and display a compact event log

4. **`--watch` flag** -- when invoked as `/forge-status --watch`:
   - Poll `.forge/progress/status.json` every 5 seconds (default, matches `background.progress_update_interval_seconds`)
   - Refresh the display with updated stage, progress, score, alerts, and model usage
   - Exit automatically when the pipeline completes (`stage` = `LEARNING` and `progress_pct` = 100) or aborts
   - If an alert appears during watch, highlight it immediately and show resolution instructions

5. If `complete: true` in state.json:
   - If `abort_reason` is present and non-empty: report "Last run aborted: {abort_reason}"
   - Otherwise: report "Last run completed successfully"
   - Show final quality score and verdict
   - Show PR URL if available
   - If `recovery_failed: true`: report "Recovery engine failed at stage {last_known_stage}"

### Hook Health

If `.forge/.hook-failures.jsonl` exists and is non-empty:
1. Count total failure entries: `wc -l < .forge/.hook-failures.jsonl`
2. Count unique hook names: `jq -r '.hook_name' .forge/.hook-failures.jsonl | sort -u | wc -l`
3. Show last 3 failures with timestamps: `tail -3 .forge/.hook-failures.jsonl | jq -r '"\(.ts)  \(.hook_name) exit=\(.exit_code)"'`
4. If count > 10: show warning "High hook failure rate. Run /forge-recover diagnose for details."

If `.forge/.hook-failures.jsonl` does not exist or is empty: show "Hooks: healthy (no failures logged)"

### Live progress

After the primary status output, print a `--- live ---` separator and
render data from `.forge/progress/status.json` and
`.forge/run-history-trends.json` (both optional):

If `.forge/progress/status.json` exists:
1. Parse via `python3 -c "import json; print(json.load(open('.forge/progress/status.json')))"`.
2. Print: `Stage: {stage}  Agent: {agent_active or 'idle'}`.
3. Print elapsed vs timeout: `{elapsed_ms_in_stage}ms / {timeout_ms}ms`.
4. If `(now - updated_at) > 60s` and `(now - state_entered_at) > stage_timeout_ms`: print "Run appears hung — consider /forge-recover diagnose."

If `.forge/run-history-trends.json` exists:
1. Print last 5 runs as a table: run_id, verdict, score, duration_s.
2. Print count of `recent_hook_failures`.

If neither file exists: print "No live data (run has not completed a
subagent dispatch yet)."

## Config validation summary

After the primary status report, emit a compact config-validation block. This
absorbs what `/forge-verify --config` used to do (that subcommand is deleted
as of Phase 2). Scope:

1. Load `.claude/forge.local.md` (if present) and `.claude/forge-config.md`.
2. Validate against PREFLIGHT constraints (`shared/preflight-constraints.md`).
3. Report each constraint as PASS/FAIL/UNCHECKED with a one-line rationale.
4. Under `--json`, emit this block as a `config_validation` top-level object:
   ```json
   {
     "config_validation": {
       "local_md_exists": true,
       "config_md_exists": true,
       "constraints": [
         { "id": "pass_threshold", "verdict": "PASS" },
         { "id": "total_retries_max", "verdict": "PASS" }
       ]
     }
   }
   ```
If `.claude/forge.local.md` is missing entirely, emit the config block with
`local_md_exists: false` and skip constraint checks (nothing to validate).

## Recent hook failures

Read the last 5 entries from `.forge/events.jsonl` where `type == "hook_failure"`.
For each, show timestamp, hook name, exit code, and a one-line stderr snippet.
If the file is missing or contains no hook_failure entries, emit "No recent
hook failures." Under `--json`, emit as a `recent_hook_failures` array.

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| state.json unparseable | Report "state.json is corrupted. Run `/forge-recover repair` to fix or `/forge-recover reset` to start fresh." and STOP |
| state.json missing fields | Show what is available, note missing fields as "unknown" |
| progress/status.json malformed | Report "Background progress data is corrupt." and fall back to state.json only |
| Stage notes file missing | Skip stage notes section, continue with other data |

## See Also

- `/forge-history` -- View trends across multiple past pipeline runs
- `/forge-recover diagnose` -- Deep diagnostic of pipeline health (state integrity, counter overflows, stalled stages)
- `/forge-recover resume` -- Resume an aborted pipeline run
- `/forge-abort` -- Stop an active pipeline run gracefully
- `/forge-insights` -- Cross-run analytics and trend analysis
