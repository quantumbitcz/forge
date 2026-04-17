---
name: forge-recover
description: "[writes] Diagnose or fix pipeline state — read-only diagnose (default), repair counters/locks, reset clearing state while preserving caches, resume from checkpoint, or rollback worktree commits. Use when pipeline stuck, failed with state errors, or you need to retry from a checkpoint. Trigger: /forge-recover, diagnose state, repair pipeline, reset state, resume from checkpoint, rollback commits"
---

# Forge Recover

Single entry point for pipeline state recovery. Replaces `/forge-diagnose`, `/forge-repair-state`, `/forge-reset`, `/forge-resume`, `/forge-rollback` (all removed in 3.0.0).

## Subcommands

| Subcommand | Read/Write | Purpose |
|---|---|---|
| `diagnose` *(default)* | read-only | Health check of state.json, recovery budget, convergence, stalled stages |
| `repair` | writes | Fix counters, stale locks, invalid stages, WAL recovery |
| `reset` | writes | Clear pipeline state (preserves cross-run caches) |
| `resume` | writes | Resume from last checkpoint |
| `rollback` | writes | Revert pipeline commits in worktree |

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: (repair/reset/rollback only) preview actions without writing
- **--json**: (diagnose only) emit structured JSON output
- **--target <branch>**: (rollback only) target branch to revert on; default = current worktree

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Examples

```
/forge-recover                          # diagnose (read-only default)
/forge-recover diagnose --json          # JSON output for scripting
/forge-recover repair --dry-run         # preview repairs
/forge-recover reset                    # prompts confirmation via AskUserQuestion
/forge-recover resume                   # continue from last checkpoint
/forge-recover rollback --target main   # revert main branch
```

## Implementation

Dispatches `fg-100-orchestrator` with `recovery_op: diagnose|repair|reset|resume|rollback` on its input payload. See `agents/fg-100-orchestrator.md` §Recovery op dispatch and `shared/state-schema.md` for the payload schema.

Replacements for removed skills:

| Old skill | New invocation |
|---|---|
| /forge-diagnose | /forge-recover diagnose |
| /forge-repair-state | /forge-recover repair |
| /forge-reset | /forge-recover reset |
| /forge-resume | /forge-recover resume |
| /forge-rollback | /forge-recover rollback |
