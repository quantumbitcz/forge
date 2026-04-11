---
name: forge-history
description: "View trends across multiple pipeline runs (score oscillations, agent effectiveness, common findings). For current run state use /forge-status."
disable-model-invocation: false
---

# Pipeline History

View trends across pipeline runs for this project.

## What to do

1. Read `.claude/forge-log.md` for run history
   - If missing: report "No pipeline history found. Run `/forge-run` to start building history."

2. Read `.forge/reports/` for detailed run reports (if available)

3. Present a summary:

   ## Pipeline Run History

   ### Quality Score Trend
   | Date | Requirement | Score | Verdict | Fix Cycles | Duration |
   |------|-------------|-------|---------|------------|----------|

   Extract from forge-log.md: each run's date, requirement summary, final quality score, verdict, total fix cycles (verify + review), and wall time.

   ### Most Common Findings
   Aggregate finding categories across all runs. Show top 5 by frequency:
   1. {CATEGORY} ({N} runs) — {typical description}

   ### Agent Effectiveness
   If agent effectiveness data exists in forge-log.md (added by retrospective):
   | Agent | Runs | Avg Time | Avg Findings | FP Rate |
   |---|---|---|---|---|

   If no effectiveness data: "Agent effectiveness tracking not yet available. Will populate after future runs."

   ### PREEMPT Health
   - Active items: {count} (HIGH: {n}, MEDIUM: {n}, LOW: {n})
   - Archived items: {count}
   - Last promotion: {date} — {item description}

   If no PREEMPT data: "No PREEMPT items found."

## Important
- This is read-only — do not modify any files
- If forge-log.md is very large (>500 lines), summarize the last 10 runs instead of all runs
- If reports directory doesn't exist, work from forge-log.md alone
