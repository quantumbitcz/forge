---
name: forge-profile
description: "Analyze pipeline performance -- time spent per stage, per agent, and per iteration. Use when a pipeline run felt slow, when you want to identify bottlenecks, or when optimizing pipeline configuration for faster runs."
allowed-tools: ['Read', 'Bash', 'Glob']
---

# /forge-profile -- Pipeline Performance Profiler

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. **Performance data exists:** Check `.forge/state.json` exists with `cost.wall_time_seconds > 0`. If no timing data: report "No performance data available. Run a pipeline first with `/forge-run`." and STOP.
4. **Events log (optional):** Check `.forge/events.jsonl` exists. If not: note that per-stage/per-agent timing analysis will be limited -- report token and convergence data from state.json only, and note that detailed timing requires events.jsonl.

## Instructions

### 1. Gather Performance Data

Read all available performance data sources:

1. **Events log** (`.forge/events.jsonl`): Parse all `state_transition` events to extract timing:
   - Per-stage duration: time between entering and leaving each stage
   - Per-agent duration: time between agent dispatch and completion events

2. **State file** (`.forge/state.json`): Extract:
   - `cost.wall_time_seconds` -- total run time
   - `tokens.by_stage` -- token consumption per stage
   - `tokens.by_agent` -- token consumption per agent
   - `convergence.phase_history` -- iteration details
   - `score_history` -- quality score progression

3. **Run reports** (`.forge/reports/*.json`): If available, extract per-run timing for trend analysis across multiple runs.

### 2. Compute Metrics

Calculate the following metrics from the gathered data:

- **Stage time share**: For each pipeline stage, compute duration as percentage of total wall time
- **Agent dispatch frequency**: Count how many times each agent was dispatched
- **Token efficiency**: Tokens consumed per score point improvement
- **Convergence cost**: Extra tokens spent in fix/review cycles beyond the first pass
- **Bottleneck identification**: Flag any stage consuming >40% of total time, or any agent dispatched >5 times

### 3. Generate Report

Present the analysis in this format:

```markdown
# Pipeline Performance Profile

## Time Breakdown by Stage
| Stage | Duration | % of Total | Iterations |
|-------|----------|-----------|------------|

## Time Breakdown by Agent
| Agent | Total Time | Dispatches | Avg per Dispatch |
|-------|-----------|-----------|-----------------|

## Token Consumption
| Component | Input Tokens | Output Tokens | Total |
|-----------|-------------|--------------|-------|

## Convergence Efficiency
- Total iterations: {N}
- Phase 1 iterations: {N}
- Phase 2 iterations: {N}
- Safety gate attempts: {N}
- Score trajectory: {start} -> {end}

## Bottleneck Analysis
- Slowest stage: {stage} ({duration}s, {pct}% of total)
- Most dispatched agent: {agent} ({count} times)
- Highest token consumer: {agent/stage}

## Recommendations
{If any stage > 40% of total time, suggest optimization}
{If any agent dispatched > 5 times, suggest scope reduction}
{If convergence took > 5 iterations, suggest PREEMPT items or threshold tuning}
```

### 4. Compare with Previous Runs

If multiple run reports exist in `.forge/reports/`, compare performance across runs:
- Show wall time trend (improving or degrading)
- Identify stages that are consistently slow
- Note if convergence efficiency is improving over time (fewer iterations per run)

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| state.json missing or unparseable | Report "Pipeline state not found or corrupt. Run `/forge-run` first." and STOP |
| events.jsonl missing | Generate partial report from state.json only, note limited data |
| events.jsonl has malformed lines | Skip malformed lines, log WARNING, continue with valid entries |
| No token data available | Report "No token usage data recorded." and skip token analysis sections |
| State corruption | Suggest `/repair-state` to fix state, then re-run profiler |

## See Also

- `/forge-insights` -- Cross-run analytics including quality trends, cost analysis, and memory health
- `/forge-history` -- View run history with scores and verdicts
- `/forge-status` -- Check current pipeline run state
- `/forge-diagnose` -- Diagnose pipeline health issues (state integrity, stalled stages)
