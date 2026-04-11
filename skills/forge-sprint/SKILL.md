---
name: forge-sprint
description: |
  Execute multiple features in parallel. Preferred over /forge-run --sprint. Reads from Linear sprint or manual feature list.
  Entry point for sprint-level orchestration.

  Usage:
    /forge-sprint                          — reads current active Linear cycle
    /forge-sprint CYC-42                   — reads specific Linear cycle
    /forge-sprint "Feature A" "Feature B"  — manual feature list
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Agent
  - TaskCreate
  - TaskUpdate
  - AskUserQuestion
  - EnterPlanMode
  - ExitPlanMode
  - neo4j-mcp
---

# Sprint Execution

Dispatch the sprint orchestrator to analyze and execute multiple features in parallel.

## Pre-Flight Checks

1. Verify no active sprint exists (check `.forge/sprint-state.json` for `status != complete|failed`)
2. If active sprint found, offer resume:
   - AskUserQuestion: "Active sprint found ({sprint_id}, {N} features, {status}). Resume / Start fresh / Abort"
3. Verify `.forge/` directory exists (create if not)

## Dispatch

```
dispatch fg-090-sprint-orchestrator "$ARGUMENTS"
```

The sprint orchestrator handles everything from here — gathering features, analyzing independence, getting user approval, dispatching pipelines, and coordinating merges.

## Resume Mode

If `$ARGUMENTS` contains `--resume` or the pre-flight check found an active sprint:
```
dispatch fg-090-sprint-orchestrator "--resume"
```

The sprint orchestrator reads `.forge/sprint-state.json` and resumes from where it left off.
