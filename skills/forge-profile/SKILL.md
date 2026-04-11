---
name: forge-profile
description: "Analyze pipeline performance -- time spent per stage, per agent, and per iteration. Identifies bottlenecks and slowest components."
allowed-tools: ['Read', 'Bash', 'Glob']
---

## Prerequisites
1. Check `.forge/state.json` exists with `cost.wall_time_seconds > 0`. If no timing data: "No performance data available. Run a pipeline first."
2. Check `.forge/events.jsonl` exists. If not: skip per-stage/per-agent timing analysis (report token + convergence data from state.json only, note that detailed timing is unavailable).

## Analysis Procedure

1. **Read events.jsonl:** Parse all `state_transition` events to extract timing:
   - Per-stage duration: time between entering and leaving each stage
   - Per-agent duration: time between agent dispatch and completion events

2. **Read state.json:** Extract:
   - `cost.wall_time_seconds` -- total run time
   - `tokens.by_stage` -- token consumption per stage
   - `tokens.by_agent` -- token consumption per agent
   - `convergence.phase_history` -- iteration details

3. **Generate report:**

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
```
