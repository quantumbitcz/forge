---
name: pipeline-history
description: View quality score trends, agent effectiveness, and run metrics across pipeline runs
disable-model-invocation: false
---

# Pipeline History

View trends across pipeline runs for this project.

## What to do

1. Read `.claude/pipeline-log.md` for run history
   - If missing: report "No pipeline history found. Run `/pipeline-run` to start building history."

2. Read `.pipeline/reports/` for detailed run reports (if available)

3. Present a summary:

   ## Pipeline Run History

   ### Quality Score Trend
   | Date | Requirement | Score | Verdict | Fix Cycles | Duration |
   |------|-------------|-------|---------|------------|----------|

   Extract from pipeline-log.md: each run's date, requirement summary, final quality score, verdict, total fix cycles (verify + review), and wall time.

   ### Most Common Findings
   Aggregate finding categories across all runs. Show top 5 by frequency:
   1. {CATEGORY} ({N} runs) — {typical description}

   ### Agent Effectiveness
   If agent effectiveness data exists in pipeline-log.md (added by retrospective):
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
- If pipeline-log.md is very large (>500 lines), summarize the last 10 runs instead of all runs
- If reports directory doesn't exist, work from pipeline-log.md alone
