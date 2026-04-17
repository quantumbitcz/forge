---
name: forge-history
description: "[read-only] View trends across multiple pipeline runs -- score oscillations, agent effectiveness, common findings, and PREEMPT health. Use when you want to see how quality has changed over time, identify recurring issues, or review past pipeline run outcomes."
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']
disable-model-invocation: false
---

# /forge-history -- Pipeline Run History

## Flags

- **--help**: print usage and exit 0
- **--json**: structured JSON output

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. **History data exists:** Check at least one of these sources:
   - `.claude/forge-log.md` with run entries
   - `.forge/reports/` with report files
   If neither exists: report "No pipeline history found. Run `/forge-run` to start building history." and STOP.

## Instructions

### 1. Gather History Data

Read all available history sources:

1. **Forge log** (`.claude/forge-log.md`): Primary source -- contains per-run entries with dates, requirements, scores, verdicts, and retrospective notes.
2. **Run reports** (`.forge/reports/`): Detailed per-run reports with findings, agent dispatches, and timing data.
3. **Learnings** (`shared/learnings/` and `.forge/learnings/`): PREEMPT items and agent effectiveness records.

If forge-log.md is very large (>500 lines), summarize the last 10 runs instead of all runs.

### 2. Present Quality Score Trend

Extract from forge-log.md each run's date, requirement summary, final quality score, verdict, total fix cycles (verify + review), and wall time:

```
## Pipeline Run History

### Quality Score Trend
| Date | Requirement | Score | Verdict | Fix Cycles | Duration |
|------|-------------|-------|---------|------------|----------|
```

Compute trend direction: improving (last 3 scores ascending), declining (descending), or stable (within oscillation tolerance).

### 3. Present Most Common Findings

Aggregate finding categories across all runs. Show top 5 by frequency:

```
### Most Common Findings
1. {CATEGORY} ({N} runs) -- {typical description}
2. ...
```

Identify findings that appear in 3+ runs as convention candidates -- patterns the team consistently triggers that should be codified as project rules.

### 4. Present Agent Effectiveness

If agent effectiveness data exists in forge-log.md (added by retrospective):

```
### Agent Effectiveness
| Agent | Runs | Avg Time | Avg Findings | FP Rate |
|---|---|---|---|---|
```

If no effectiveness data: report "Agent effectiveness tracking not yet available. Will populate after future runs."

### 5. Present PREEMPT Health

Read learnings files for PREEMPT items:

```
### PREEMPT Health
- Active items: {count} (HIGH: {n}, MEDIUM: {n}, LOW: {n})
- Archived items: {count}
- Last promotion: {date} -- {item description}
- Decay candidates: {count} items with 10+ unused runs
```

If no PREEMPT data: report "No PREEMPT items found."

### 6. Cross-Run Trend Summary

Synthesize the data into actionable observations:
- Score trajectory over the last 5 runs
- Whether convergence is getting faster or slower
- Top recurring finding that should become a convention

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| forge-log.md missing | Fall back to reports directory. If also missing, STOP with guidance |
| forge-log.md unparseable | Report "forge-log.md has unexpected format. Showing raw content summary." and display what can be extracted |
| Reports directory empty | Work from forge-log.md alone, note limited data |
| State corruption | This skill is read-only and does not depend on state.json |

## Important

- This is read-only -- do not modify any files
- If forge-log.md is very large (>500 lines), summarize the last 10 runs instead of all runs
- If reports directory does not exist, work from forge-log.md alone

## See Also

- `/forge-status` -- Check the current (active) pipeline run state
- `/forge-insights` -- Deeper cross-run analytics with cost analysis, convergence patterns, and memory health
- `/forge-profile` -- Detailed performance profiling of a single pipeline run
- `/forge-diagnose` -- Diagnose pipeline health issues when something looks wrong
