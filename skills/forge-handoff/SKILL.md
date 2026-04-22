---
name: forge-handoff
description: "[writes] Create, list, show, resume, or search forge session handoffs. Use when context is getting heavy and you want to transfer a forge run or conversation into a fresh Claude Code session, or to resume from a prior handoff artefact. Subcommands - no args (write), list, show, resume, search."
allowed-tools: ['Read', 'Bash', 'AskUserQuestion']
ui: { ask: true }
---

# /forge-handoff

Manage forge session handoffs — structured artefacts that preserve run state for continuation in a fresh Claude Code session.

## Flags

- **--help**: print usage and exit 0
- **--run <id>**: (list only) scope to a specific run_id

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Subcommand dispatch

| Invocation                                      | Behaviour                                                                 |
|-------------------------------------------------|---------------------------------------------------------------------------|
| `/forge-handoff`                                | Write a full-variant manual handoff for the current run                   |
| `/forge-handoff list [--run <id>]`              | List handoff chain for the current or specified run                       |
| `/forge-handoff show <path\|latest>`            | Print a handoff's contents (`latest` = most recent for current run)       |
| `/forge-handoff resume [<path>]`                | Structured resume — parses, checks staleness, seeds state, delegates      |
| `/forge-handoff search <query>`                 | FTS5 full-text search across all handoffs in `run-history.db`             |

### Subcommand: write (no args)

Writes a full-variant handoff for the current run (if any). In interactive mode, uses AskUserQuestion to confirm slug and variant. In autonomous mode, silently writes.

Calls: `python3 -m hooks._py.handoff.cli write --level manual`

### Subcommand: list

Lists handoff chain for the current run or the specified run.

Calls: `python3 -m hooks._py.handoff.cli list [--run <id>]`

### Subcommand: show

Prints a handoff's contents to stdout. `latest` picks the most recent handoff for the current run.

Calls: `python3 -m hooks._py.handoff.cli show <path|latest>`

### Subcommand: resume

Structured resume. Parses handoff, checks staleness, seeds state.json, delegates to `/forge-recover resume <run_id>`. With no args, picks the most recent un-SHIPPED handoff.

Calls: `python3 -m hooks._py.handoff.cli resume [<path>]`

### Subcommand: search

FTS5 full-text search over all handoffs in `run-history.db`.

Calls: `python3 -m hooks._py.handoff.cli search "<query>"`

## Instructions

Route the user invocation to the matching subcommand via `python3 -m hooks._py.handoff.cli`. Surface the CLI's stdout to the user. When `resume` returns a `run_id`, delegate to `/forge-recover resume <run_id>` so the orchestrator picks up from the seeded checkpoint.

## Behaviour

- Path: `.forge/runs/<run_id>/handoffs/YYYY-MM-DD-HHMMSS-<level>-<slug>.md`
- Levels: `soft`, `hard`, `milestone`, `terminal`, `manual`
- File survives `/forge-recover reset`
- Config: see `shared/preflight-constraints.md#handoff` for defaults
- Spec: see ADR `docs/adr/0012-session-handoff-as-state-projection.md`

## Error Handling

| Condition                                     | Action                                                              |
|-----------------------------------------------|---------------------------------------------------------------------|
| No active forge run                           | Report "No active run. Nothing to hand off." STOP                   |
| Handoff file missing (show/resume)            | CLI exits non-zero; surface "Handoff not found: <path>" and STOP    |
| Stale handoff (git_head drift, checkpoint gap)| Resumer returns STALE verdict; ask user to confirm or abort          |
| Rate limit hit (manual writes)                | CLI emits "Rate limited — 15min window"; STOP unless terminal level |
| Redaction pattern match                       | Handoff is written with secret redacted inline; no user prompt       |
| FTS5 index corrupt                            | Search returns empty result set with stderr warning; STOP            |

## See Also

- `/forge-recover resume` — structured continuation from checkpoint
- `/forge-status` — current run state
- `shared/preflight-constraints.md#handoff` — config defaults
- `docs/adr/0012-session-handoff-as-state-projection.md` — design rationale

## Examples

```bash
# Write a handoff now
/forge-handoff

# List all handoffs for current run
/forge-handoff list

# Resume from a specific handoff
/forge-handoff resume .forge/runs/20260421-a3f2/handoffs/2026-04-21-143022-soft-add-health.md

# Resume from latest (auto-pick)
/forge-handoff resume

# Find past discussions
/forge-handoff search "cache layer decision"
```
