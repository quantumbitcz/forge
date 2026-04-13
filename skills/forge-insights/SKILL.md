---
name: forge-insights
description: "Analyze trends across pipeline runs -- quality trajectory, agent effectiveness, cost analysis, convergence patterns, memory health. Use when you want to understand how pipeline quality has evolved, identify cost optimization opportunities, or review agent and memory effectiveness across runs."
allowed-tools: ['Read', 'Bash', 'Glob']
---

# /forge-insights — Pipeline Run Analytics

Analyze trends across pipeline runs to surface actionable insights about quality, cost, agent behavior, and pipeline health.

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. **Run history exists:** Check at least one of these sources exists:
   - `.forge/reports/` with report files
   - `.forge/state.json` with `telemetry` data
   - `.claude/forge-log.md` with run entries
   If none exist: report "No pipeline run data found. Run `/forge-run` to generate data, then try again." and STOP.

## Instructions

### 1. Gather Data

Read all available data sources:

1. **Run reports** (`.forge/reports/*.json` or `.forge/reports/*.md`): per-run summaries including scores, findings, timings, agent dispatches.
2. **Telemetry** (`.forge/state.json` → `telemetry`): current/last run metrics — token usage, wall time, stage durations, agent dispatch counts.
3. **Forge log** (`.claude/forge-log.md`): human-readable run history with dates, requirements, scores, verdicts, and retrospective notes.
4. **Learnings** (`shared/learnings/` and `.forge/learnings/`): accumulated patterns, PREEMPT items, agent effectiveness records.
5. **Score history** (`.forge/state.json` → `score_history`): per-iteration score progression within the current/last run.

If a source is unavailable, skip it and note which categories will have incomplete data.

### 2. Analyze — Five Insight Categories

#### Category 1: Quality Trajectory

Analyze score trends across runs:

- **Score trend:** Plot scores from all available runs. Indicate direction (improving, declining, stable).
- **Recurring findings:** Identify finding categories that appear in 3+ runs. These are convention candidates.
- **Severity distribution shift:** Compare CRITICAL/WARNING/INFO ratios between early and recent runs.
- **Convention candidates:** Findings that recur but never get permanently fixed suggest missing conventions or team patterns that should be codified.

```markdown
### Quality Trajectory

| Run | Date | Score | Verdict | CRITICALs | WARNINGs |
|-----|------|-------|---------|-----------|----------|
| {n} | {date} | {score} | {verdict} | {count} | {count} |

**Trend:** {improving/declining/stable} ({delta} over {n} runs)

**Recurring Findings (3+ runs):**
| Category | Occurrences | Last Seen | Suggestion |
|----------|-------------|-----------|------------|
| {cat}    | {n}         | {date}    | {codify as convention / investigate root cause} |
```

#### Category 2: Agent Effectiveness

Analyze which agents contribute most to quality improvement:

- **Most impactful reviewer:** Agent whose findings lead to the largest score improvements after fixing.
- **Least triggered agent:** Reviewer that rarely produces findings — may indicate over-scoping or irrelevance to this project.
- **Mutation kill rate:** If mutation testing data exists (from test gate), report the kill rate trend.
- **False positive rate:** Agents with high FP rates (findings marked as dismissed or not-applicable).

```markdown
### Agent Effectiveness

| Agent | Dispatches | Avg Findings | Score Impact | FP Rate |
|-------|-----------|-------------|-------------|---------|
| {agent} | {n} | {avg} | {delta} | {pct}% |

**Most impactful:** {agent} — avg {delta} point improvement per dispatch
**Least triggered:** {agent} — {n} findings across {m} runs
**Mutation kill rate:** {pct}% (trend: {direction})
```

#### Category 3: Cost Analysis

Analyze resource consumption:

- **Average run cost:** Total tokens (input + output) per run, converted to approximate USD if token pricing is known.
- **Most expensive stage:** Stage consuming the most tokens on average.
- **Routing savings:** Estimate tokens saved by correct mode routing (bugfix vs standard, quick review vs full).
- **Convergence cost:** Extra tokens spent in fix/review cycles beyond the first pass.

```markdown
### Cost Analysis

| Metric | Value |
|--------|-------|
| Avg tokens per run | {n} |
| Avg wall time | {duration} |
| Most expensive stage | {stage} ({pct}% of tokens) |
| Convergence overhead | {pct}% of total (fix cycles: {avg_n}) |

**Stage Breakdown:**
| Stage | Avg Tokens | Avg Duration | % of Total |
|-------|-----------|-------------|-----------|
| {stage} | {tokens} | {duration} | {pct}% |
```

#### Category 4: Convergence Patterns

Analyze how efficiently the pipeline converges to shipping quality:

- **Average iterations to ship:** Mean total iterations across runs.
- **Plateau causes:** Most common reasons for score plateaus (conflicting findings, over-strict rules, flaky tests).
- **Safety gate failure rate:** How often the safety gate rejects and forces a phase restart.
- **First-pass success rate:** Percentage of runs that pass quality on the first verify+review cycle.

```markdown
### Convergence Patterns

| Metric | Value |
|--------|-------|
| Avg iterations to ship | {n} |
| First-pass success rate | {pct}% |
| Safety gate failure rate | {pct}% |
| Most common plateau cause | {cause} |

**Iteration Distribution:**
| Iterations | Runs | % |
|-----------|------|---|
| 1-2       | {n}  | {pct}% |
| 3-5       | {n}  | {pct}% |
| 6+        | {n}  | {pct}% |
```

#### Category 5: Memory Health

Analyze the accumulated knowledge base:

- **Active PREEMPT items:** Count by priority (HIGH/MEDIUM/LOW), identify items nearing decay.
- **Auto-discovered patterns:** Patterns added by retrospective that have been applied in subsequent runs.
- **Decay candidates:** PREEMPT items with 10+ unused runs approaching demotion or archival.
- **Learning growth:** Rate of new learnings per run.

```markdown
### Memory Health

**PREEMPT Items:**
| Priority | Active | Applied (last 5 runs) | Decay Candidates |
|----------|--------|-----------------------|------------------|
| HIGH     | {n}    | {n}                   | {n}              |
| MEDIUM   | {n}    | {n}                   | {n}              |
| LOW      | {n}    | {n}                   | {n}              |
| ARCHIVED | {n}    | —                     | —                |

**Pattern Discovery:**
- Total auto-discovered patterns: {n}
- Applied in subsequent runs: {n} ({pct}%)
- Never applied: {n} (review for removal)

**Learnings Growth:**
- Total learnings files: {n}
- New entries (last 5 runs): {n}
- Most active category: {category}
```

### 3. Generate Summary and Recommendations

Synthesize the five categories into actionable recommendations:

```markdown
## Pipeline Insights Report

**Project:** {project name}
**Runs analyzed:** {count}
**Date range:** {earliest} to {latest}

{Category 1-5 sections as above}

### Recommendations

| Priority | Action | Category | Expected Impact |
|----------|--------|----------|-----------------|
| {1-N}    | {specific action} | {category} | {what improves} |
```

Prioritize recommendations by expected impact:

1. **Recurring CRITICALs** — codify as project conventions or fix root cause.
2. **High convergence cost** — tune thresholds or add PREEMPT items for common patterns.
3. **Low-value agents** — consider disabling agents with zero findings across 5+ runs.
4. **Stale PREEMPT items** — archive items that never match to reduce overhead.
5. **Score regression** — investigate if a recent config change degraded quality.

### 4. Save Report

Write the full report to `.forge/reports/insights-{date}.md` where `{date}` is today in `YYYY-MM-DD` format. If the reports directory does not exist, create it.

## Important

- This is READ-ONLY with respect to project code. Only writes to `.forge/reports/`.
- If only one data source is available, generate a partial report and note which categories have insufficient data.
- Do not fabricate data. If a metric cannot be computed, report "Insufficient data" rather than estimating.
- For projects with fewer than 3 runs, note that trend analysis requires more data points and focus on single-run metrics instead.
- Token-to-USD conversion is approximate. Use $3/MTok input, $15/MTok output as defaults unless project config specifies otherwise.

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| No run data available | Report "No pipeline run data found. Run `/forge-run` to generate data, then try again." and STOP |
| Only one data source available | Generate partial report and note which categories have insufficient data |
| Fewer than 3 runs | Note that trend analysis requires more data points. Focus on single-run metrics |
| Report directory does not exist | Create `.forge/reports/` before writing the report |
| Data source unparseable | Skip the malformed source, log WARNING, continue with remaining sources |
| State corruption | This skill reads state.json for telemetry but does not depend on valid pipeline state |

## See Also

- `/forge-history` -- View run history with scores and verdicts (simpler than insights)
- `/forge-profile` -- Detailed performance profiling of a single pipeline run
- `/forge-status` -- Check current pipeline run state
- `/forge-diagnose` -- Diagnose pipeline health issues for the current run
