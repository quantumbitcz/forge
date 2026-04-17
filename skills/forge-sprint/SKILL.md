---
name: forge-sprint
description: "[writes] Execute multiple features in parallel via sprint orchestration. Use when you have multiple independent features to build, a Linear sprint cycle to execute, or when you want parallel pipeline runs for faster delivery."
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
ui: { ask: true, tasks: true }
---

# /forge-sprint -- Sprint Execution

Dispatch the sprint orchestrator to analyze and execute multiple features in parallel.

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: preview actions without writing

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. **No active sprint:** Check `.forge/sprint-state.json` for `status != complete|failed`. If active sprint found, offer resume via AskUserQuestion: "Active sprint found ({sprint_id}, {N} features, {status}). Resume / Start fresh / Abort"
4. **Forge directory:** Verify `.forge/` directory exists (create if not)

## What to Expect

After dispatch, fg-090-sprint-orchestrator will:
1. Analyze features for independence (can they run in parallel?)
2. Create isolated worktrees per feature
3. Run parallel pipeline instances (one per feature)
4. Merge results and create PRs

Total time: 15-60 minutes depending on feature count and complexity. Features with shared file conflicts run sequentially.

## Instructions

### Usage

```
/forge-sprint                          -- reads current active Linear cycle
/forge-sprint CYC-42                   -- reads specific Linear cycle
/forge-sprint "Feature A" "Feature B"  -- manual feature list
```

### Dispatch

```
dispatch fg-090-sprint-orchestrator "$ARGUMENTS"
```

The sprint orchestrator handles everything from here -- gathering features, analyzing independence, getting user approval, dispatching pipelines, and coordinating merges.

### Resume Mode

If `$ARGUMENTS` contains `--resume` or the pre-flight check found an active sprint:
```
dispatch fg-090-sprint-orchestrator "--resume"
```

The sprint orchestrator reads `.forge/sprint-state.json` and resumes from where it left off.

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| No features provided and Linear unavailable | Ask user to provide features manually: `/forge-sprint "Feature A" "Feature B"` |
| Sprint orchestrator dispatch fails | Report "Sprint orchestrator failed to start. Check plugin installation." and STOP |
| Active sprint conflict | Offer resume, fresh start, or abort via AskUserQuestion |
| Individual feature pipeline fails | Sprint orchestrator handles per-feature failure. Failed features do not block others |
| State corruption | Suggest `/forge-repair-state` for state.json issues, or `/forge-reset` to start fresh |

## See Also

- `/forge-run` -- Run a single feature (use `--sprint` flag for quick parallel dispatch)
- `/forge-shape` -- Shape vague features into structured specs before sprinting
- `/forge-status` -- Check progress of active sprint runs
- `/forge-abort` -- Stop an active sprint gracefully
