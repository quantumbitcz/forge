---
name: forge-recover
description: "[writes] Diagnose or fix pipeline state — read-only diagnose (default), repair counters/locks, reset clearing state while preserving caches, resume from checkpoint, rollback worktree commits, rewind to any prior checkpoint (time-travel), or list the checkpoint DAG. Use when pipeline stuck, failed with state errors, or you need to explore alternate execution paths. Trigger: /forge-recover, diagnose state, repair pipeline, reset state, resume from checkpoint, rollback commits, rewind checkpoint, time travel, list checkpoints"
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'AskUserQuestion']
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
| `rewind --to=<id> [--force]` | writes | Time-travel to any checkpoint. Atomic four-tuple restore (state, worktree, events, memory). Aborts on dirty worktree unless `--force`. |
| `list-checkpoints [--json]` | read-only | Render the checkpoint DAG with current HEAD marked. |

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: (repair/reset/rollback only) preview actions without writing
- **--json**: (diagnose only) emit structured JSON output
- **--target <branch>**: (rollback only) target branch to revert on; default = current worktree
- **--to <id>**: (rewind only) target checkpoint human id (e.g. `PLAN.-.003`) or sha256. Required.
- **--force**: (rewind only) proceed even if worktree is dirty. Destructive — loses uncommitted changes.

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | success |
| 1 | generic failure |
| 2 | usage error (missing --to, etc.) |
| 5 | rewind aborted: dirty worktree (use `--force` to override) |
| 6 | rewind aborted: unknown checkpoint id |
| 7 | rewind aborted: another rewind transaction in progress |

See `shared/skill-contract.md` for the standard exit-code table.

## Prerequisites

- `.forge/state.json` exists (for `diagnose`, `resume`, `repair`, `rollback` subcommands)
- Git repository (for `rollback`)

## Instructions

Dispatch `fg-100-orchestrator` with `recovery_op` set to the subcommand name. See `agents/fg-100-orchestrator.md` §Recovery op dispatch for routing details. The orchestrator reads the current `.forge/state.json`, routes to the appropriate recovery strategy (per `shared/recovery/recovery-engine.md`), and applies the operation atomically via `shared/forge-state-write.sh`.

## Error Handling

Exit codes per `shared/skill-contract.md`:

- 0: success
- 1: bad args
- 3: recovery needed
- 4: aborted by user

## See Also

- `/forge-abort` -- Stop an active pipeline run before attempting recovery
- `/forge-status` -- Check pipeline state to decide which recovery subcommand to use
- `/forge-history` -- Review prior run outcomes when planning a rollback

## References

- `shared/skill-contract.md` — standard exit codes and flag conventions
- `shared/state-schema.md` — state.json schema and recovery fields
- `agents/fg-100-orchestrator.md` — recovery dispatch routing

## Examples

```
/forge-recover                          # diagnose (read-only default)
/forge-recover diagnose --json          # JSON output for scripting
/forge-recover repair --dry-run         # preview repairs
/forge-recover reset                    # prompts confirmation via AskUserQuestion
/forge-recover resume                   # continue from last checkpoint
/forge-recover rollback --target main   # revert main branch
/forge-recover list-checkpoints             # show DAG with HEAD marked
/forge-recover list-checkpoints --json      # machine-readable
/forge-recover rewind --to=PLAN.-.003       # time-travel restore
/forge-recover rewind --to=a3f9c1 --force   # override dirty worktree guard
```

## Implementation

Dispatches `fg-100-orchestrator` with `recovery_op: diagnose|repair|reset|resume|rollback|rewind|list-checkpoints` on its input payload. See `agents/fg-100-orchestrator.md` §Recovery op dispatch and `shared/state-schema.md` for the payload schema. Rewind and list-checkpoints are backed by `hooks/_py/time_travel/` (invoked as `python3 -m hooks._py.time_travel`; see `shared/recovery/time-travel.md`).

Replacements for removed skills:

| Old skill | New invocation |
|---|---|
| /forge-diagnose | /forge-recover diagnose |
| /forge-repair-state | /forge-recover repair |
| /forge-reset | /forge-recover reset |
| /forge-resume | /forge-recover resume |
| /forge-rollback | /forge-recover rollback |
