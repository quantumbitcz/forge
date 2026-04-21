---
name: forge-handoff
description: "[writes] Create, list, show, resume, or search forge session handoffs. Use when context is getting heavy and you want to transfer a forge run or conversation into a fresh Claude Code session, or to resume from a prior handoff artefact. Subcommands - no args (write), list, show, resume, search."
allowed-tools: ['Read', 'Bash', 'AskUserQuestion']
ui: { ask: true }
---

# /forge-handoff

Manage forge session handoffs — structured artefacts that preserve run state for continuation in a fresh Claude Code session.

## Subcommands

### `/forge-handoff` (no args) — write a handoff now

Writes a full-variant handoff for the current run (if any). In interactive mode, uses AskUserQuestion to confirm slug and variant. In autonomous mode, silently writes.

Calls: `python3 -m hooks._py.handoff.cli write --level manual`

### `/forge-handoff list [--run <id>]`

Lists handoff chain for the current run or the specified run.

Calls: `python3 -m hooks._py.handoff.cli list [--run <id>]`

### `/forge-handoff show <path|latest>`

Prints a handoff's contents to stdout. `latest` picks the most recent handoff for the current run.

Calls: `python3 -m hooks._py.handoff.cli show <path|latest>`

### `/forge-handoff resume [<path>]`

Structured resume. Parses handoff, checks staleness, seeds state.json, delegates to `/forge-recover resume <run_id>`. With no args, picks the most recent un-SHIPPED handoff.

Calls: `python3 -m hooks._py.handoff.cli resume [<path>]`

### `/forge-handoff search <query>`

FTS5 full-text search over all handoffs in `run-history.db`.

Calls: `python3 -m hooks._py.handoff.cli search "<query>"`

## Behaviour

- Path: `.forge/runs/<run_id>/handoffs/YYYY-MM-DD-HHMMSS-<level>-<slug>.md`
- Levels: `soft`, `hard`, `milestone`, `terminal`, `manual`
- File survives `/forge-recover reset`
- Config: see `shared/preflight-constraints.md#handoff` for defaults
- Spec: `docs/superpowers/specs/2026-04-21-session-handoff-design.md`

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
