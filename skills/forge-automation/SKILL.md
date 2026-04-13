---
name: forge-automation
description: "Manage event-driven pipeline automations -- list, add, remove, and test triggers. Use when you want to set up automatic pipeline runs on CI failures, PR events, cron schedules, or file changes."
disable-model-invocation: false
---

# /forge-automation — Automation Manager

Manage event-driven pipeline automations configured in `forge-config.md`. Full contract: `shared/automations.md`.

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. **Config exists:** Check `.claude/forge-config.md` exists. If not: report "No forge-config.md found. Run /forge-init to generate." and STOP.

## Arguments

Parse `$ARGUMENTS` for subcommand:

- `list` (default if no argument) — show all configured automations
- `add` — interactive wizard to create a new automation
- `remove` — select and remove an existing automation
- `test <name>` — simulate a trigger for the named automation
- `log` — show recent automation log entries

## Instructions

### 1. List Automations

Read `.claude/forge-config.md` and parse the `automations:` YAML array.

If the array is empty or missing: report "No automations configured. Use `/forge-automation add` to create one." and STOP.

Display as a table:

```
## Configured Automations

| # | Name | Trigger | Action | Filter | Cooldown | Enabled |
|---|------|---------|--------|--------|----------|---------|
| 1 | ci-failure-fix | ci_failure | forge-fix | branch: main | 30m | yes |
| 2 | pr-review | pr_opened | forge-review | base_branch: main | 5m | yes |
| 3 | scheduled-health | cron | codebase-health | cron: 0 3 * * 1 | 1440m | yes |
```

For each automation, show the filter as a compact `key: value` summary (multiple filters comma-separated). Show `enabled` as "yes" or "no" (default "yes" if field is absent).

### 2. Add Automation

Use `AskUserQuestion` for each required field in sequence:

**Step 1 — Trigger type:**

Ask: "What event should trigger this automation?"

Options:
- `cron` — Run on a schedule (cron expression)
- `ci_failure` — Run when CI fails (requires GitHub Actions workflow)
- `pr_opened` — Run when a PR is opened (requires GitHub Actions workflow)
- `dependabot_pr` — Run when Dependabot opens a PR (requires GitHub Actions workflow)
- `linear_status` — Run when a Linear ticket changes status (requires Linear MCP)
- `file_changed` — Run when a file matching a pattern is edited (PostToolUse hook)

**Step 2 — Action:**

Ask: "Which forge skill should this automation invoke?"

Options (list the most common, allow free text):
- `forge-fix` — Auto-fix the issue
- `forge-review` — Review changed files
- `codebase-health` — Full codebase analysis (read-only)
- `security-audit` — Run security scanners
- `forge-run` — Full pipeline
- `forge-diagnose` — Read-only diagnostic
- Other (type skill name)

**Step 3 — Filter:**

Based on the selected trigger type, ask for the relevant filter fields per `shared/automations.md` Filter Fields by Trigger table:

| Trigger | Prompt |
|---------|--------|
| `cron` | "Enter cron expression (5-field, e.g. `0 3 * * 1` for Monday 3 AM):" |
| `ci_failure` | "Filter to branch (glob, e.g. `main`, `release/*`; leave blank for all):" then "Filter to workflow filename (e.g. `ci.yml`; leave blank for all):" |
| `pr_opened` | "Filter to base branch (e.g. `main`; leave blank for all):" then "Exclude authors (comma-separated logins, e.g. `dependabot[bot]`; leave blank for none):" |
| `dependabot_pr` | "Filter to base branch (leave blank for all):" then "Dependency type (`production` or `development`; leave blank for all):" |
| `linear_status` | "From status (e.g. `In Progress`; leave blank for any):" then "To status (e.g. `Done`):" |
| `file_changed` | "File glob pattern (e.g. `src/**/*.ts`):" then "Exclusion glob (leave blank for none):" |

**Step 4 — Cooldown:**

Ask: "Cooldown in minutes between consecutive firings (minimum 1):"

Default suggestion based on trigger type: `cron` = 1440, `ci_failure` = 30, `pr_opened` = 5, `dependabot_pr` = 10, `linear_status` = 15, `file_changed` = 5.

**Step 5 — Name:**

Ask: "Automation name (unique identifier, e.g. `nightly-health`, `ci-fix-main`):"

Validate: name must be unique among existing automations. If duplicate, ask again.

**Step 6 — Confirm:**

Display the complete automation definition as YAML and ask: "Add this automation to forge-config.md?"

On confirmation, append the new entry to the `automations:` array in `.claude/forge-config.md`. If the `automations:` key does not exist, create it with the new entry. Preserve all other content in the file.

If the trigger is `cron`, also register it via `CronCreate` with the cron expression. Report success.

If the trigger is `ci_failure`, `pr_opened`, or `dependabot_pr`, remind the user: "This trigger requires a GitHub Actions workflow. See `shared/automations.md` CI Integration section for the workflow template."

### 3. Remove Automation

1. List all automations (same as List).
2. If none exist: report "No automations to remove." and STOP.
3. Use `AskUserQuestion`: "Which automation do you want to remove?" with each automation name as an option.
4. Confirm: "Remove automation '{name}'? This cannot be undone."
5. On confirmation, remove the entry from the `automations:` array in `.claude/forge-config.md`. Preserve all other content.
6. If the removed automation had trigger type `cron`, note: "If a cron job was registered for this automation, it remains active until the session ends. Use `/schedule` to manage active cron jobs."
7. Report: "Removed automation '{name}'."

### 4. Test Trigger

Simulate what would happen if a trigger fires for the named automation, without actually dispatching the skill.

1. Parse automation name from `$ARGUMENTS` (e.g. `/forge-automation test ci-failure-fix`).
2. Find the automation in `forge-config.md`. If not found: report "Automation '{name}' not found." and STOP.
3. Check enabled status. If `enabled: false`: report "Automation '{name}' is disabled. It would not fire." and STOP.
4. Check cooldown: read `.forge/automation-log.jsonl` (if it exists) for the most recent entry with `automation == name` and `result` in (`success`, `failure`). Compute elapsed time since `ts`.
   - If elapsed < `cooldown_minutes`: report "COOLDOWN ACTIVE. {remaining} minutes remaining. Trigger would be dropped with result: `skipped_cooldown`."
   - If no previous entry or elapsed >= `cooldown_minutes`: report "Cooldown clear."
5. Check concurrent limit: count entries in `.forge/automation-log.jsonl` with `result == "success"` and no corresponding completion (heuristic: entries within the last 10 minutes without a subsequent entry for the same automation). If >= 3: report "CONCURRENT LIMIT. 3 automations already running. Trigger would queue."
6. Check safety: if the action is destructive (`forge-run`, `forge-fix`, `deep-health`, `migration`), note: "This is a destructive action. Would pause for user confirmation before executing."
7. Report the simulation result:

```
## Trigger Simulation: {name}

| Check | Result |
|-------|--------|
| Enabled | yes/no |
| Cooldown | clear / active ({remaining}m remaining) |
| Concurrency | ok / queued (3/3 slots in use) |
| Safety gate | none / would require confirmation |

**Would execute:** `{action}` with trigger context from `{trigger}` type.
**Would NOT actually dispatch.** Use the real trigger mechanism to execute.
```

### 5. View Log

Read `.forge/automation-log.jsonl`. If missing or empty: report "No automation log entries. Automations have not fired yet." and STOP.

Parse each line as JSON. Display the most recent 20 entries (newest first):

```
## Automation Log (last 20 entries)

| Timestamp | Automation | Trigger | Action | Result | Duration |
|-----------|------------|---------|--------|--------|----------|
| 2026-04-12 03:00 | scheduled-health | cron | codebase-health | success | 45.2s |
| 2026-04-12 02:15 | ci-failure-fix | ci_failure | forge-fix | skipped_cooldown | - |
```

Format `duration_ms` as seconds with one decimal. Omit duration for skipped entries (show `-`). Truncate timestamp to minutes.

If entries have `error` field (non-null), append a section:

```
### Recent Errors
- **{automation}** ({ts}): {error}
```

## Error Handling

- **forge-config.md parse failure:** Report "Could not parse automations from forge-config.md. Check YAML syntax." and STOP.
- **automation-log.jsonl parse failure:** Skip malformed lines, log WARNING, continue with valid entries.
- **CronCreate failure during add:** Log WARNING: "Could not register cron job. The automation is saved in config but the cron schedule is not active. Try `/schedule` to manage cron jobs manually."

## Important

- **Read-only by default.** Only `add` and `remove` modify `forge-config.md`. All other subcommands are read-only.
- **Never dispatch skills.** The `test` subcommand simulates only. Actual dispatch is handled by the automation engine (`hooks/automation-trigger.sh`).
- **Never modify `.forge/automation-log.jsonl`.** That file is append-only, written by the automation engine.
- **Preserve file content.** When editing `forge-config.md`, only modify the `automations:` section. Never alter other configuration.

## See Also

- `/forge-run` -- The pipeline that automations typically invoke
- `/forge-fix` -- Common action for CI failure automations
- `/forge-review` -- Common action for PR opened automations
- `/codebase-health` -- Common action for scheduled health check automations
- `/config-validate` -- Validate forge-config.md after modifying automations
