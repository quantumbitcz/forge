---
name: forge-admin
description: "[writes] Manage forge state and configuration: recovery, abort, config edits, session handoff, automations, playbooks, output compression, knowledge graph maintenance. Use to recover from broken pipeline state, edit settings, manage long-lived state."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'AskUserQuestion']
---

# /forge-admin — State Management Surface

Two-level dispatch: top-level `<area>` (recover, abort, config, handoff, automation, playbooks, refine, compress, graph) and per-area `<action>` where applicable. No NL fallback — unknown areas print help and exit 2.

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: preview only (where applicable)
- **--json**: structured JSON output (status-like subcommands only)

## Exit codes

See `shared/skill-contract.md` for the standard table.

## Subcommand dispatch

Follow `shared/skill-subcommand-pattern.md`. **Positional, no NL fallback.**

**Dispatch rules:**

1. Read `$ARGUMENTS`.
2. Split: `AREA="$1"; shift; ACTION="$1"; shift; REST="$*"`.
3. If `$AREA` is empty OR matches `-*`: print usage and exit 2.
4. If `$AREA == --help` or `help`: print usage and exit 0.
5. If `$AREA` is in `{recover, abort, config, handoff, automation, playbooks, refine, compress, graph}`: dispatch to `### Subcommand: <AREA>` with `$ACTION` and `$REST`.
6. Otherwise: print `Unknown area '<AREA>'. Valid: recover | abort | config | handoff | automation | playbooks | refine | compress | graph. Try /forge-admin --help.` and exit 2.

## Usage

```
/forge-admin <area> [<action>] [args]

Areas:
  recover <action>          State recovery (diagnose | repair | reset | resume | rollback | rewind | list)
  abort                     Stop active pipeline run gracefully
  config [<action>]         Config editor (wizard | <key=val>)
  handoff [<action>]        Session handoff (list | show | resume | search | <text>)
  automation [<action>]     Event-driven triggers (list | add | remove | test)
  playbooks [<action>]      Reusable recipes (list | run <id> | create | analyze)
  refine [<playbook-id>]    Apply playbook refinement proposals
  compress [<action>]       Token compression (agents | output <mode> | status | help)
  graph <action>            Knowledge graph (init | status | query <cypher> | rebuild | debug)

Flags:
  --help                    Show this message
  --dry-run                 Preview only (where applicable)
  --json                    Structured output (status-like subcommands)
```

## Shared prerequisites

Before any subcommand:

1. **Git repository:** `git rev-parse --show-toplevel`. If fails: STOP.
2. **Forge initialized:** `.claude/forge.local.md` exists. If absent: report "Forge not initialized. Run /forge first." and STOP. (This skill does NOT auto-bootstrap; bootstrap is a `/forge` concern.)

---

### Subcommand: recover

State diagnostics and repair. Actions: `diagnose | repair | reset | resume | rollback | rewind | list`.

Default action when none provided: `diagnose` (read-only, safe default).

#### Action: diagnose (read-only, default)

Read `.forge/state.json`, `.forge/.lock`, recent events; report stuck stage, missing checkpoints, lock holders, score history. No mutations.

Step 0: Delegate state read. Run `/forge-status --json` and parse the JSON
output. Embed the result as a top-level `state` field in the diagnose
report. Do NOT read `.forge/state.json` directly — the orchestrator and
forge-status own that path; recovery consumes the parsed snapshot.

Recovery recommendations (the "what to do next" logic) remain `/forge-admin recover`'s responsibility; only the raw state read is delegated.

#### Action: repair

Reset counters, clear stale `.forge/.lock` (>24h), normalize state to a known-good shape. Preserves explore-cache, plan-cache, code-graph.db, run-history.db, wiki, learnings.

#### Action: reset

Clear `.forge/state.json` and worktree state. Preserves: `.forge/explore-cache.json`, `.forge/plan-cache/`, `.forge/code-graph.db`, `.forge/trust.json`, `.forge/events.jsonl`, `.forge/playbook-analytics.json`, `.forge/run-history.db`, `.forge/playbook-refinements/`, `.forge/consistency-cache.jsonl`, `.forge/plans/candidates/`, `.forge/runs/<id>/handoffs/`, `.forge/wiki/`, `.forge/brainstorm-transcripts/`. Confirms via `AskUserQuestion` unless `--autonomous`.

#### Action: resume

Continue from last checkpoint. Reads `.forge/state.json.head_checkpoint`, validates checkpoint integrity, dispatches `fg-100-orchestrator` with resume context.

#### Action: rollback

Roll back worktree commits to last good checkpoint. Confirms via `AskUserQuestion` (destructive).

#### Action: rewind <checkpoint-id>

Rewind to any prior checkpoint in the DAG (time-travel). Lists candidates if no `<checkpoint-id>` given.

Flags:

- **--to <id>**: target checkpoint human id (e.g. `PLAN.-.003`) or sha256. Required.
- **--force**: proceed even if worktree is dirty. Destructive — loses uncommitted changes.

Exit codes:

- 5: rewind aborted: dirty worktree (use `--force` to override)
- 6: rewind aborted: unknown checkpoint id
- 7: rewind aborted: another rewind transaction in progress

#### Action: list

Print checkpoint DAG with timestamps, scores, and stage labels.

#### Recover dispatch

All recover actions dispatch `fg-100-orchestrator` with `recovery_op` set to the action name. See `agents/fg-100-orchestrator.md` §Recovery op dispatch for routing details. The orchestrator reads the current `.forge/state.json`, routes to the appropriate recovery strategy (per `shared/recovery/recovery-engine.md`), and applies the operation atomically via `shared/forge-state-write.sh`. Rewind and list are backed by `hooks/_py/time_travel/` (invoked as `python3 -m hooks._py.time_travel`; see `shared/recovery/time-travel.md`).

#### Recover examples

```
/forge-admin recover                                # diagnose (read-only default)
/forge-admin recover diagnose --json                # JSON output for scripting
/forge-admin recover repair --dry-run               # preview repairs
/forge-admin recover reset                          # prompts confirmation via AskUserQuestion
/forge-admin recover resume                         # continue from last checkpoint
/forge-admin recover rollback --target main         # revert main branch
/forge-admin recover list                           # show DAG with HEAD marked
/forge-admin recover list --json                    # machine-readable
/forge-admin recover rewind --to=PLAN.-.003         # time-travel restore
/forge-admin recover rewind --to=a3f9c1 --force     # override dirty worktree guard
```

### Subcommand: abort

Stop active pipeline run gracefully. Writes ABORT marker to state, releases `.forge/.lock`, preserves checkpoints. Compatible with `/forge-admin recover resume`.

#### Abort prerequisites

1. Check `.forge/state.json` exists. If not: "No active pipeline to abort." STOP.
2. Read `story_state` from state.json. If `COMPLETE` or `ABORTED`: "Pipeline already finished (state: {story_state})." STOP.

#### Abort instructions

1. **Read current state:** `story_state`, `convergence.phase`, `total_iterations`
2. **Confirm with user via AskUserQuestion:**
   "Pipeline is at stage {story_state}, iteration {total_iterations}. How would you like to proceed?"
   - Option 1: "Abort and preserve state for resume"
   - Option 2: "Abort and reset (equivalent to /forge-admin recover reset)"
   - Option 3: "Cancel — keep running"
3. **If option 1 (preserve):**
   a. Transition to ABORTED via the state machine:
      `bash shared/forge-state.sh transition user_abort_direct --forge-dir .forge`
   b. Release `.forge/.lock` if held: `rm -f .forge/.lock`
   c. Do NOT delete worktree (preserves work for resume)
   d. Report: "Pipeline aborted at {stage}. State preserved. Run /forge-admin recover resume to continue."
4. **If option 2 (reset):** Delegate to `/forge-admin recover reset`
5. **If option 3 (cancel):** "Abort cancelled. Pipeline continues."

**Important:** Never write directly to state.json. Always use `forge-state.sh transition` to maintain state machine integrity.

#### Post-Abort State

- `story_state: ABORTED`
- `previous_state`: preserved for /forge-admin recover resume
- All counters preserved
- Worktree preserved
- Lock released

#### Abort error handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| state.json missing | Report "No active pipeline to abort." and STOP |
| Pipeline already finished | Report "Pipeline already finished (state: {story_state})." and STOP |
| State transition fails | Report "Could not transition to ABORTED state. State machine error: {error}." Suggest `/forge-admin recover repair` |
| Lock file removal fails | Log WARNING. Lock file will be detected as stale on next run |
| state.json write fails | Report error. State may be partially updated. Suggest `/forge-admin recover repair` |
| State corruption | Attempt abort anyway via state machine. If that fails, suggest `/forge-admin recover reset` |

### Subcommand: config

Interactive config editor. Actions: `wizard` (full multi-question setup) or `<key=val>` (single-key edit).

#### Config operations

| Command | Action |
|---------|--------|
| `/forge-admin config` | Show current config summary |
| `/forge-admin config set <key> <value>` | Set a config value |
| `/forge-admin config add <key> <value>` | Add to list field (e.g., code_quality) |
| `/forge-admin config remove <key> <value>` | Remove from list field |
| `/forge-admin config validate` | Run validation (delegates to /forge-status) |
| `/forge-admin config show <section>` | Show specific section (components, scoring, convergence, caveman) |
| `/forge-admin config diff` | Show changes since last pipeline run |
| `/forge-admin config wizard` | Run the full bootstrap wizard |

#### Config prerequisites

1. Verify `.claude/forge.local.md` or `.claude/forge-config.md` exists. If neither: "No forge configuration found. Run `/forge-init` first." STOP.

#### Action: wizard

Run the full bootstrap wizard (lifted from old `/forge-init`). Detects stack via `bootstrap-detect.py`, asks for overrides, writes `.claude/forge.local.md`.

#### Action: show (default, no arguments)

1. Read `.claude/forge.local.md` and `.claude/forge-config.md`
2. Display summary: components, scoring thresholds, convergence settings, enabled features
3. Highlight any validation warnings

#### Action: set

1. Parse key path and new value from `$ARGUMENTS` (e.g., `set components.testing vitest`)
2. Run `${CLAUDE_PLUGIN_ROOT}/shared/validate-config.sh` with the proposed change
3. If ERROR: show error message with suggestion, do NOT apply
4. If WARNING: show warning and ask user to confirm
5. If PASS: apply change to appropriate file
   - `components.*` → `forge.local.md`
   - `scoring.*`, `convergence.*`, `caveman.*` → `forge-config.md`
6. Show before/after diff

#### Action: add / remove

1. Parse key and value from `$ARGUMENTS`
2. Verify key is a list field (e.g., `code_quality`)
3. For `add`: append value if not already present
4. For `remove`: delete value if present, warn if not found
5. Validate after change

#### Action: <key=val>

Parse `<key>=<val>`, validate against `shared/preflight-constraints.md`, write to `.claude/forge.local.md`. Surfaces validation errors.

#### Action: validate

Delegates to `/forge-status` (Config validation section). Shows results inline.

#### Action: diff

1. Read current config from `forge.local.md` and `forge-config.md`
2. Read last pipeline state from `.forge/state.json` (if exists)
3. Show fields that changed since last run
4. If no `.forge/state.json`: show "No previous run to compare against"

#### Config safeguards

- **Locked sections:** `<!-- locked -->` fences in `forge-config.md` cannot be modified. Show: "This value is locked. Remove the <!-- locked --> fence to unlock."
- **Auto-tuned values:** Values previously modified by retrospective (fg-700) show warning: "This value was auto-tuned by the pipeline. Override? [y/n]"
- **Always validate:** Every `set`/`add`/`remove` operation runs validation before applying
- **Show diff:** Always show before/after diff before applying changes

#### Config error handling

| Condition | Action |
|-----------|--------|
| Config file missing | Suggest: "Run /forge-init first" |
| Invalid key path | Show valid keys from config-schema.json |
| Invalid value | Show valid values with fuzzy suggestion |
| Locked section | Refuse edit, explain how to unlock |

### Subcommand: handoff

Session handoff. Default action (no args, `<text>` arg) = write. Actions: `list | show | resume | search | <text>`.

Manage forge session handoffs — structured artefacts that preserve run state for continuation in a fresh Claude Code session.

#### Handoff flags

- **--help**: print usage and exit 0
- **--run <id>**: (list only) scope to a specific run_id

#### Handoff dispatch table

| Invocation                                              | Behaviour                                                                 |
|---------------------------------------------------------|---------------------------------------------------------------------------|
| `/forge-admin handoff`                                  | Write a full-variant manual handoff for the current run                   |
| `/forge-admin handoff list [--run <id>]`                | List handoff chain for the current or specified run                       |
| `/forge-admin handoff show <path\|latest>`              | Print a handoff's contents (`latest` = most recent for current run)       |
| `/forge-admin handoff resume [<path>]`                  | Structured resume — parses, checks staleness, seeds state, delegates      |
| `/forge-admin handoff search <query>`                   | FTS5 full-text search across all handoffs in `run-history.db`             |

#### Action: <text> (or default with args)

Write a structured handoff artefact to `.forge/runs/<run_id>/handoffs/<timestamp>.md` capturing run state, conversation context, and resume instructions.

Writes a full-variant handoff for the current run (if any). In interactive mode, uses AskUserQuestion to confirm slug and variant. In autonomous mode, silently writes.

Calls: `python3 -m hooks._py.handoff.cli write --level manual`

#### Action: list

List handoff artefacts in reverse chronological order.

Calls: `python3 -m hooks._py.handoff.cli list [--run <id>]`

#### Action: show <id>

Display the handoff artefact body. `latest` picks the most recent handoff for the current run.

Calls: `python3 -m hooks._py.handoff.cli show <path|latest>`

#### Action: resume <id>

Pre-fill the current Claude Code session with the handoff context (memory + state restoration).

Structured resume. Parses handoff, checks staleness, seeds state.json, delegates to `/forge-admin recover resume <run_id>`. With no args, picks the most recent un-SHIPPED handoff.

Calls: `python3 -m hooks._py.handoff.cli resume [<path>]`

#### Action: search <query>

FTS5 search over `.forge/runs/*/handoffs/*.md`.

Calls: `python3 -m hooks._py.handoff.cli search "<query>"`

#### Handoff instructions

Route the user invocation to the matching action via `python3 -m hooks._py.handoff.cli`. Surface the CLI's stdout to the user. When `resume` returns a `run_id`, delegate to `/forge-admin recover resume <run_id>` so the orchestrator picks up from the seeded checkpoint.

#### Handoff behaviour

- Path: `.forge/runs/<run_id>/handoffs/YYYY-MM-DD-HHMMSS-<level>-<slug>.md`
- Levels: `soft`, `hard`, `milestone`, `terminal`, `manual`
- File survives `/forge-admin recover reset`
- Config: see `shared/preflight-constraints.md#handoff` for defaults
- Spec: see ADR `docs/adr/0012-session-handoff-as-state-projection.md`

#### Handoff error handling

| Condition                                     | Action                                                              |
|-----------------------------------------------|---------------------------------------------------------------------|
| No active forge run                           | Report "No active run. Nothing to hand off." STOP                   |
| Handoff file missing (show/resume)            | CLI exits non-zero; surface "Handoff not found: <path>" and STOP    |
| Stale handoff (git_head drift, checkpoint gap)| Resumer returns STALE verdict; ask user to confirm or abort          |
| Rate limit hit (manual writes)                | CLI emits "Rate limited — 15min window"; STOP unless terminal level |
| Redaction pattern match                       | Handoff is written with secret redacted inline; no user prompt       |
| FTS5 index corrupt                            | Search returns empty result set with stderr warning; STOP            |

#### Handoff examples

```bash
# Write a handoff now
/forge-admin handoff

# List all handoffs for current run
/forge-admin handoff list

# Resume from a specific handoff
/forge-admin handoff resume .forge/runs/20260421-a3f2/handoffs/2026-04-21-143022-soft-add-health.md

# Resume from latest (auto-pick)
/forge-admin handoff resume

# Find past discussions
/forge-admin handoff search "cache layer decision"
```

### Subcommand: automation

Event-driven trigger management. Actions: `list | add | remove | test`.

Backed by `hooks/automation_trigger.py`. Triggers: cron, CI failure, PR event, file change.

Manage event-driven pipeline automations configured in `forge-config.md`. Full contract: `shared/automations.md`.

#### Automation prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. **Config exists:** Check `.claude/forge-config.md` exists. If not: report "No forge-config.md found. Run /forge-init to generate." and STOP.

#### Automation arguments

Parse `$ARGUMENTS` for sub-action:

- `list` (default if no argument) — show all configured automations
- `add` — interactive wizard to create a new automation
- `remove` — select and remove an existing automation
- `test <name>` — simulate a trigger for the named automation
- `log` — show recent automation log entries

#### Action: list

Read `.claude/forge-config.md` and parse the `automations:` YAML array.

If the array is empty or missing: report "No automations configured. Use `/forge-admin automation add` to create one." and STOP.

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

#### Action: add

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
- `forge-admin recover diagnose` — Read-only diagnostic
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

#### Action: remove

1. List all automations (same as List).
2. If none exist: report "No automations to remove." and STOP.
3. Use `AskUserQuestion`: "Which automation do you want to remove?" with each automation name as an option.
4. Confirm: "Remove automation '{name}'? This cannot be undone."
5. On confirmation, remove the entry from the `automations:` array in `.claude/forge-config.md`. Preserve all other content.
6. If the removed automation had trigger type `cron`, note: "If a cron job was registered for this automation, it remains active until the session ends. Use `/schedule` to manage active cron jobs."
7. Report: "Removed automation '{name}'."

#### Action: test

Simulate what would happen if a trigger fires for the named automation, without actually dispatching the skill.

1. Parse automation name from `$ARGUMENTS` (e.g. `/forge-admin automation test ci-failure-fix`).
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

#### Action: log

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

#### Automation error handling

- **forge-config.md parse failure:** Report "Could not parse automations from forge-config.md. Check YAML syntax." and STOP.
- **automation-log.jsonl parse failure:** Skip malformed lines, log WARNING, continue with valid entries.
- **CronCreate failure during add:** Log WARNING: "Could not register cron job. The automation is saved in config but the cron schedule is not active. Try `/schedule` to manage cron jobs manually."

#### Automation important

- **Read-only by default.** Only `add` and `remove` modify `forge-config.md`. All other sub-actions are read-only.
- **Never dispatch skills.** The `test` sub-action simulates only. Actual dispatch is handled by the automation engine (`hooks/automation_trigger.py`).
- **Never modify `.forge/automation-log.jsonl`.** That file is append-only, written by the automation engine.
- **Preserve file content.** When editing `forge-config.md`, only modify the `automations:` section. Never alter other configuration.

### Subcommand: playbooks

Reusable pipeline recipes. Actions: `list | run <id> | create | analyze`.

Backed by `.forge/playbooks/` YAML and `.forge/playbook-analytics.json`.

List all available playbooks (project-specific and built-in) with their descriptions, parameter details, and usage analytics.

#### Playbooks flags

- **--help**: print usage and exit 0
- **--json**: structured JSON output

#### Playbooks prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. **Playbooks enabled:** Read `playbooks.enabled` from `forge-config.md`. If `false`: report "Playbooks are disabled. Set `playbooks.enabled: true` in forge-config.md." and STOP.

#### Action: list (default)

Discover playbooks:

1. **Project playbooks:** Read `playbooks.directory` from `forge-config.md` (default: `.claude/forge-playbooks`). Glob for `*.md` files in that directory.
2. **Built-in playbooks:** Glob for `*.md` files in `${CLAUDE_PLUGIN_ROOT}/shared/playbooks/`.
3. Merge lists. If a project playbook has the same name as a built-in, the project version wins. Mark overridden built-ins with "(overridden by project)".

For each discovered playbook:

1. Read the YAML frontmatter to extract: `name`, `description`, `version`, `parameters`, `tags`, `acceptance_criteria`.
2. Validate that `name` matches the filename (sans `.md`). If mismatch, note it as a warning.
3. Count the number of acceptance criteria.
4. Count the number of parameters (required vs optional).

Load analytics:

1. Check if `.forge/playbook-analytics.json` exists.
2. If it exists, read it and match playbook entries by name.
3. Extract per-playbook: `run_count`, `success_count`, `avg_score`, `last_used`.
4. If analytics file does not exist or is corrupt, report "No analytics data yet" for all playbooks.

Display playbooks grouped by source (project first, then built-in):

```markdown
## Available Playbooks

### Project Playbooks (.claude/forge-playbooks/)

| Playbook | Description | Params | Runs | Avg Score | Last Used |
|----------|-------------|--------|------|-----------|-----------|
| `{name}` | {description} | {required}/{total} | {run_count} | {avg_score} | {last_used or "never"} |

### Built-In Playbooks

| Playbook | Description | Params | Runs | Avg Score | Last Used |
|----------|-------------|--------|------|-----------|-----------|
| `{name}` | {description} | {required}/{total} | {run_count} | {avg_score} | {last_used or "never"} |

---

### Usage

To run a playbook:
  /forge-run --playbook={name} param1=value1 param2=value2

To see playbook details:
  /forge-admin playbooks {name}
```

#### Action: <name> (detail view)

If `$ARGUMENTS` contains a playbook name, show the detailed view for that specific playbook:

```markdown
## Playbook: {name}

**Description:** {description}
**Version:** {version}
**Mode:** {mode}
**Tags:** {tags | join:", "}
**Source:** {project or built-in}

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `{name}` | {type} | {yes/no} | {default or "-"} | {description} |

### Acceptance Criteria

1. {ac_1}
2. {ac_2}
...

### Review Focus

- Categories: {focus_categories | join:", "}
- Min score: {min_score}
- Review agents: {review_agents | join:", "}

### Analytics

| Metric | Value |
|--------|-------|
| Total runs | {run_count} |
| Success rate | {success_count}/{run_count} ({pct}%) |
| Average score | {avg_score} |
| Average iterations | {avg_iterations} |
| Average duration | {avg_duration_seconds}s |
| Average cost | ${avg_cost_usd} |
| Last used | {last_used} |

### Common Findings

| Category | Occurrences |
|----------|-------------|
| {category} | {count} |

### Example

  /forge-run --playbook={name} {example_params}
```

#### Playbooks important

- This is READ-ONLY. Never modify playbook files or analytics.
- Always show clickable file paths for each playbook.
- If no playbooks exist (no project playbooks and built-ins disabled), report: "No playbooks available. Create playbooks in `.claude/forge-playbooks/` or enable built-in playbooks with `playbooks.builtin_playbooks: true`."
- Analytics data may be absent for new playbooks. Show "never" and "0" for playbooks without runs.

#### Playbooks error handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| No playbooks found | Report "No playbooks available" with instructions to create or enable built-ins |
| Playbook frontmatter invalid | Skip playbook, log WARNING with filename and parse error |
| Analytics file corrupt | Report "Analytics data unavailable (corrupt file)" and list playbooks without stats |
| Playbook name mismatch | Log WARNING: "Playbook {filename} has name={name} in frontmatter (should match filename)" |
| Requested detail view for nonexistent playbook | Report "Playbook '{name}' not found" and list available playbooks |

### Subcommand: refine

Apply playbook refinement proposals from `.forge/playbook-refinements/`. Optional `<playbook-id>` filter. Interactive review/apply via `AskUserQuestion`.

Review and apply improvement proposals generated from pipeline run data. Proposals are evidence-backed suggestions for making playbooks produce better code.

#### Refine prerequisites

1. **Forge initialized:** `.claude/forge.local.md` exists
2. **Run history exists:** `.forge/run-history.db` exists
3. **Proposals available:** `.forge/playbook-refinements/` has at least one file

If prerequisites fail, STOP with guidance:
- No run history → "Run the pipeline first to generate data."
- No proposals → "No refinement proposals yet. Run playbooks 3+ times to generate proposals."

#### Refine arguments

`$ARGUMENTS` = optional playbook_id. If omitted, list playbooks with pending proposals.

#### Refine instructions

##### No playbook_id provided

1. List all `.forge/playbook-refinements/*.json` files
2. For each, show: playbook_id, proposal count, confidence distribution
3. Ask user to select one

##### Playbook selected

1. Read `.forge/playbook-refinements/{playbook_id}.json`
2. Filter to `status: ready` proposals only
3. If no ready proposals: "All proposals for {playbook_id} have been processed."
4. For each ready proposal, present via AskUserQuestion:

```
## Proposal: {id}
**Type:** {type}
**Target:** {target}
**Confidence:** {confidence} ({agreement})

**Current:** {current_value}
**Proposed:** {proposed_value}

**Evidence:** {evidence}
**Expected Impact:** {impact_estimate}
```

Options:
- **Accept** — Apply this refinement to the playbook
- **Reject** — Dismiss this proposal permanently
- **Modify** — Accept with changes (ask for modified value)
- **Defer** — Skip for now, revisit later

##### Applying accepted proposals

1. Locate playbook file:
   - Project: `.claude/forge-playbooks/{playbook_id}.md`
   - Built-in: `shared/playbooks/{playbook_id}.md`
   - If built-in, copy to `.claude/forge-playbooks/` first (project override)
2. Edit the playbook frontmatter/body per proposal type:
   - `scoring_gap` / `acceptance_gap` → append to `acceptance_criteria:` list
   - `stage_focus` → modify `stages.focus` array
   - `parameter_default` → modify `parameters[].default`
3. Increment `version` in playbook frontmatter
4. Update `.forge/playbook-refinements/{playbook_id}.json`:
   - Set accepted proposals to `status: applied`
   - Set rejected proposals to `status: rejected`
   - Set deferred proposals to `status: deferred`
5. Log to `forge-log.md`: `[REFINE-APPLIED] {playbook_id} v{old}→v{new}: {proposal_ids}`

#### Refine guard rails

- Respect `<!-- locked -->` fences in playbook files — skip proposals targeting locked sections
- Never modify `pass_threshold`, `concerns_threshold`, or scoring weights
- Never remove VERIFYING, REVIEWING, or SHIPPING from stages

#### Refine error handling

- Playbook file not found → STOP: "Playbook {id} not found in project or built-in playbooks."
- Locked section targeted → skip proposal, inform user: "Proposal {id} targets a locked section. Skipped."
- Write fails → STOP with error, do not update refinement file status

### Subcommand: compress

Token-cost compression controls. Actions: `agents | output <mode> | status | help`.

Single entry point for compression. Replaces `/forge-compress` (previous agent-only surface), `/forge-caveman`, and `/forge-compression-help` (all removed in 3.0.0).

#### Compress sub-actions

| Sub-action | Read/Write | Purpose |
|---|---|---|
| `agents` | writes | Compress agent `.md` files via terse-rewrite (30–50% reduction) |
| `output <mode>` | writes | Set output compression. mode ∈ {off, lite, full, ultra}. Writes .forge/caveman-mode |
| `status` *(default)* | read-only | Show current agent-compression ratio and output-mode |
| `help` | read-only | Reference card (flags, modes, token savings by mode, tips) |

#### Compress flags

- **--help**: print usage and exit 0
- **--dry-run**: (agents, output) preview without writing
- **--json**: (status, help) structured output

#### Compress prerequisites

- Forge plugin installed and `agents/` directory present (for `agents` sub-action)
- `.forge/` directory writable (for `output` sub-action, which persists `.forge/caveman-mode`)

#### Action: agents

Compress agent `.md` files via terse rewriting (30-50% reduction). Confirms via `AskUserQuestion`.

Compress all `agents/fg-*.md` files via terse rewriting; preserves code blocks, YAML frontmatter, and all technical rules. See `shared/output-compression.md` and `shared/agent-ui.md`.

#### Action: output <mode>

Set runtime output compression. `<mode>` is `off | lite | full | ultra`. Writes `.forge/caveman-mode`.

Write the mode string (`off|lite|full|ultra`) to `.forge/caveman-mode`. The runtime reads this at agent dispatch time to select the per-stage compression level.

#### Action: status

Print current compression settings (read-only).

Read current agent file sizes and `.forge/caveman-mode`, report ratios.

#### Action: help

Print compression reference card. Emit the reference card inline.

#### Compress error handling

Exit codes per `shared/skill-contract.md`:

- 0: success
- 1: bad args (e.g., unknown mode passed to `output`)
- 2: validation failure
- 4: aborted by user

#### Compress examples

```
/forge-admin compress                            # default: status
/forge-admin compress output lite                # set lite mode
/forge-admin compress output ultra --dry-run     # preview ultra without writing
/forge-admin compress agents                     # compress all agent .md
/forge-admin compress agents --dry-run           # preview compression
/forge-admin compress help                       # reference card
/forge-admin compress status --json              # JSON for scripting
```

#### Compress modes (output sub-action)

| Mode | Token savings | Description |
|------|---------------|-------------|
| off | 0% | Full verbose output (default) |
| lite | ~30% | Strip redundant narration; keep code/data intact |
| full | ~55% | Aggressive prose compression; ellipsis-heavy |
| ultra | ~75% | Caveman grammar; skeletal output only |

### Subcommand: graph

Knowledge-graph operations. Actions: `init | status | query <cypher> | rebuild | debug`.

**Read-only enforcement (AC-S014):** the `query` action MUST reject any Cypher containing `CREATE | MERGE | DELETE | SET | REMOVE | DROP` (case-insensitive) before sending to Neo4j. Use a regex pre-check; if matched, abort with exit 2 and message "Read-only mode: only MATCH queries permitted. Use `/forge-admin graph rebuild` for writes."

#### Graph dispatch

Follow `shared/skill-subcommand-pattern.md`. This sub-area uses **positional sub-actions**, NOT flags.

**Dispatch rules:**

1. Read `$ARGUMENTS`.
2. Split: `SUB="$1"; shift; REST="$*"`.
3. If `$SUB` is empty OR matches `-*` (bare invocation or flags-only): print the usage block and exit 2 (`No sub-action provided. Valid: init | status | query | rebuild | debug.`).
4. If `$SUB == --help` OR `$SUB == help`: print usage and exit 0.
5. If `$SUB` is in `{init, status, query, rebuild, debug}`: dispatch to the matching `#### Action: <SUB>` section with `$REST` as its arguments.
6. Otherwise: print `Unknown sub-action '<SUB>'. Valid: init | status | query | rebuild | debug. Try /forge-admin graph --help.` and exit 2.

**No default sub-action.** This is intentional — `rebuild` is destructive, so a bare `/forge-admin graph` must not silently rebuild.

#### Graph flags

- **--help**: print usage and exit 0
- **--dry-run**: preview actions without writing (applicable to `init`, `rebuild`)
- **--json**: structured JSON output (applicable to `status`, `debug`)

Sub-action-specific flags are documented under each sub-action section.

#### Graph prerequisites

Before any sub-action:

1. **Forge initialized:** `.claude/forge.local.md` exists. If not: "Pipeline not initialized. Run `/forge-init` first." STOP.
2. **Graph enabled:** `graph.enabled: true` in `forge.local.md`. If false/absent: "Graph integration is disabled. Set `graph.enabled: true` to use this feature." STOP.
3. **Docker available:** `docker info`. If fails: "Docker is not available. Cannot run graph operations." STOP.

#### Graph container name resolution

Read `graph.neo4j_container_name` from `.claude/forge.local.md`. If not set, default: `forge-neo4j`. Use the resolved name in ALL `docker` commands below.

#### Action: init

You are the graph initializer. Your job is to start the Neo4j container, import the plugin seed data, and build the project codebase graph. Be idempotent — detect what is already done and skip those steps.

##### Step 1: VERIFY PREREQUISITES

1. Check that `.claude/forge.local.md` exists in the project root.
   - If it does not exist: **ERROR** — "Pipeline not initialized. Run `/forge-init` first." Abort.

2. Read `.claude/forge.local.md` and check `graph.enabled`.
   - If `graph.enabled: false` or the `graph:` section is absent: inform the user — "Graph integration is disabled in `forge.local.md`. Set `graph.enabled: true` to use this feature." Exit.

3. Check Docker availability: `docker info`
   - If the command fails: **WARN** — "Docker is not available. Cannot start Neo4j container."
   - Update `.forge/state.json` integrations: `"neo4j": {"available": false}`
   - Abort.

##### Step 2: PREPARE COMPOSE FILE

Copy the Docker Compose template to the pipeline working directory:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/shared/graph/docker-compose.neo4j.yml" .forge/docker-compose.neo4j.yml
```

Substitute port variables from config (read `graph.neo4j_port` and `graph.neo4j_bolt_port` from `forge.local.md`, defaulting to `7474` and `7687` respectively). Edit the copied file to replace placeholder values with the resolved ports.

##### Step 3: START CONTAINER

Check if the container is already running:

```bash
docker ps --filter "name=forge-neo4j" --format "{{.Names}}"
```

- If `forge-neo4j` appears in output: **skip** this step — container is already running.
- If not running: first check if the Neo4j image exists locally:

```bash
docker image inspect neo4j:5-community >/dev/null 2>&1
```

- If image NOT present: pull it explicitly first. This may take a moment on first run:

```bash
docker pull neo4j:5-community
```

- Then start the container:

```bash
docker compose -f .forge/docker-compose.neo4j.yml up -d
```

**Important:** The image tag `neo4j:5-community` uses a major-version floating tag, which always resolves to the latest 5.x release. This is intentional — Neo4j 5.x is backward-compatible within the major version. Do NOT pin to a specific patch version as it would require manual updates.

##### Step 4: WAIT FOR HEALTH

Poll the health check script until Neo4j is ready, up to 60 seconds:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/neo4j-health.sh"
```

Run this in a loop (every 3 seconds) until it exits 0 or 60 seconds have elapsed.

- If Neo4j becomes healthy within 60s: continue.
- If it does not respond after 60s: **ERROR** — "Neo4j did not become healthy within 60 seconds. Check container logs: `docker logs forge-neo4j`" Abort.

##### Step 5: IMPORT PLUGIN SEED

Check for the seed marker node to determine if the seed has already been imported:

```bash
echo "MATCH (n:_SeedMarker {id: 'forge-seed-v2'}) RETURN count(n)" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain
```

- If count > 0: **skip** — seed already imported.
- If count = 0: import the seed:

```bash
cat "${CLAUDE_PLUGIN_ROOT}/shared/graph/seed.cypher" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local
```

##### Step 6: BUILD PROJECT GRAPH

Check `.forge/graph/.last-build-sha` — if it exists and matches the current `git rev-parse HEAD`, the graph is already up to date for this commit; skip rebuild and note this to the user.

###### Project Identity

After container startup, derive project_id:
```bash
PROJECT_ID=$(derive_project_id "$PROJECT_ROOT")
```

Pass to build-project-graph.sh:
```bash
./shared/graph/build-project-graph.sh --project-root "$PROJECT_ROOT" --project-id "$PROJECT_ID"
```

For monorepo with components, iterate each component:
```bash
for component in $(read_components "$PROJECT_ROOT"); do
  ./shared/graph/build-project-graph.sh --project-root "$PROJECT_ROOT" --project-id "$PROJECT_ID" --component "$component"
done
```

Otherwise, build the project graph:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/build-project-graph.sh" --project-root . | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local
```

After success, write the current commit SHA to `.forge/graph/.last-build-sha`.

Create `.forge/graph/` directory if it does not exist.

##### Step 7: UPDATE STATE

Update `.forge/state.json` integrations block:

```json
"neo4j": {
  "available": true
}
```

If `.forge/state.json` does not exist or has no `integrations` key, create/add the key. Do not overwrite unrelated fields.

##### Step 8: REPORT

Query and display node counts:

```bash
echo "MATCH (n) RETURN labels(n)[0] AS label, count(*) AS count ORDER BY count DESC" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain
```

Present a summary:

```
Graph initialized successfully.

  Container:   forge-neo4j (running)
  Seed:        imported
  Build SHA:   <sha>

  Node counts:
    ProjectFile        142
    ProjectClass        38
    ProjectFunction    215
    ...

  Run /forge-admin graph query to explore the graph.
  Run /forge-admin graph status for health and coverage details.
```

Note any steps that were skipped (idempotency).

Key behavior preserved:
- Idempotent: skips steps that are already done (container running, seed imported, build-SHA matches HEAD).
- Writes `.forge/graph/.last-build-sha` on success.
- Updates `.forge/state.json.integrations.neo4j.available = true`.
- Pulls `neo4j:5-community` if image not present locally.

#### Action: status

You are the graph status reporter. Your job is to display the current state of the Neo4j knowledge graph: container health, node and relationship counts, last build SHA, and enrichment coverage.

Read-only. Honors `--json` flag per skill-contract §2.

##### Status additional prerequisites

- **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
- **Neo4j available:** Check Docker container running. If not: report "Neo4j not running. Run `/forge-admin graph init` first." and STOP.

##### Step 1: CONTAINER HEALTH

Run the health check script:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/neo4j-health.sh"
```

- If exit 0: container is healthy — note status as **HEALTHY**.
- If non-zero: container is not responding — note status as **UNAVAILABLE** and show the error output.

Also check the container's running state:

```bash
docker ps --filter "name=forge-neo4j" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

If Docker itself is unavailable, report: "Docker is not available. Cannot check graph status."

###### Per-Project Node Counts

Show node counts grouped by project:
```cypher
MATCH (n) WHERE n.project_id IS NOT NULL
RETURN n.project_id, labels(n)[0] AS label, count(n) AS count
ORDER BY n.project_id, label
```

##### Step 2: NODE COUNTS

If Neo4j is healthy, query node counts by label:

```bash
echo "MATCH (n) RETURN labels(n)[0] AS label, count(*) AS count ORDER BY count DESC" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain
```

Display all results in a table.

##### Step 3: LAST BUILD SHA

Read `.forge/graph/.last-build-sha` and display its contents.

- If the file does not exist: show "No build recorded yet."
- If the file exists: also compare to `git rev-parse HEAD` and indicate whether the graph is **up to date** or **stale** (HEAD has moved since last build).

##### Step 4: ENRICHMENT COVERAGE

Read `.forge/graph/.enriched-files` if it exists.

- Show total number of enriched files.
- Show percentage of project source files covered (compare to total files tracked by git: `git ls-files | wc -l`).
- If the file does not exist: show "No enrichment data recorded."

##### Step 5: RELATIONSHIP COUNTS

If Neo4j is healthy, query relationship counts:

```bash
echo "MATCH ()-[r]->() RETURN type(r) AS type, count(*) AS count ORDER BY count DESC" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain
```

Display all results in a table.

##### Step 6: REPORT

Present a consolidated status summary:

```
Knowledge Graph Status

  Container:         HEALTHY (forge-neo4j)
  Ports:             7474 (HTTP), 7687 (Bolt)

  Last build:        abc1234  (up to date)

  Node counts:
    ProjectFile        142
    ProjectClass        38
    ProjectFunction    215
    ProjectPackage      12
    ProjectDependency   27
    _SeedMarker          1

  Relationship counts:
    CONTAINS           180
    CALLS               94
    IMPORTS             61
    DEPENDS_ON          27

  Enrichment coverage: 89/142 files (63%)

  Run /forge-admin graph init to rebuild if stale.
  Run /forge-admin graph query <cypher> to explore.
```

If Neo4j is unavailable, show what can be determined from local files (last build SHA, enriched files) and suggest running `/forge-admin graph init`.

#### Action: query <cypher>

You are the graph query executor. Your job is to accept a Cypher query (everything after `query` on the command line), validate that the graph is available, execute the query, and display formatted results.

Takes the Cypher query as a positional argument. If no argument: prompts the user. Read-only.

##### Read-only pre-check (AC-S014)

Before sending any query to Neo4j, run a regex pre-check on the query string. If the query (case-insensitive) matches any of `CREATE | MERGE | DELETE | SET | REMOVE | DROP`, abort with exit 2 and the message:

```
Read-only mode: only MATCH queries permitted. Use `/forge-admin graph rebuild` for writes.
```

Reference regex (case-insensitive): `\b(CREATE|MERGE|DELETE|SET|REMOVE|DROP)\b`

##### Query additional prerequisites

- **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
- **Neo4j available:** Check Docker container running. If not: report "Neo4j not running. Run `/forge-admin graph init` first." and STOP.

##### Step 1: CHECK AVAILABILITY

Run the health check script:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/neo4j-health.sh"
```

- If Neo4j is not healthy: **ERROR** — "Neo4j is not available. Run `/forge-admin graph init` to start the graph." Abort.

###### Default Parameters

Inject `project_id` automatically into all queries:
```bash
PROJECT_ID=$(derive_project_id "$PROJECT_ROOT")
```

User can override by specifying their own `:param project_id` in the query, or omit `project_id` for cross-project queries.

##### Step 2: GET QUERY

Accept the Cypher query from the skill argument (the text following `query` on the command line).

- If no argument is provided: prompt the user — "Enter your Cypher query:"
- Wait for the user to type the query before proceeding.

Store the query in `$QUERY`.

##### Step 3: EXECUTE QUERY

Run the query against Neo4j (after the read-only pre-check has passed):

```bash
echo "$QUERY" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain
```

Capture both stdout and stderr.

- If the command exits 0: display the results (see Step 4).
- If it exits non-zero: display the error output and suggest checking query syntax. Do not retry automatically.

##### Step 4: FORMAT AND DISPLAY RESULTS

Present the raw output from cypher-shell. If the output is empty (no rows returned), show: "Query returned no results."

Also show the query that was executed, so the user can reference or modify it:

```
Query:
  MATCH (n:ProjectClass) RETURN n.name LIMIT 10

Results:
  n.name
  ------
  UserService
  OrderRepository
  PaymentGateway
  ...

  (3 rows)
```

If the output is large (more than 50 rows), truncate display to 50 rows and note: "Showing first 50 of N rows. Add a LIMIT clause to restrict results."

##### Step 5: FOLLOW-UP

After displaying results, offer useful next steps based on the query type:

- If the query was a `MATCH ... RETURN` with no LIMIT: suggest adding `LIMIT` for large graphs.
- If the query returned 0 results: suggest checking node labels with `MATCH (n) RETURN DISTINCT labels(n)`.
- Always remind the user they can run `/forge-admin graph status` to see all available labels and relationship types.

#### Action: rebuild

You are the graph rebuilder. Your job is to wipe all project-derived nodes from the knowledge graph and rebuild them from the current codebase. The plugin seed graph (framework conventions, patterns, rules) is preserved.

Honors `--component <name>`, `--clear-enrichment`, and `--dry-run` flags. Uses `AskUserQuestion` for the confirmation step. Destructive — deletes project-scoped nodes (preserves plugin seed).

##### Rebuild additional prerequisites

- **Git repository:** Run `git rev-parse --is-inside-work-tree`. If not: report "Not a git repository." and STOP.
- **Neo4j available:** Run the health check script. If not healthy: report "Neo4j is not available. Run `/forge-admin graph init` to start the graph first." and STOP.

##### Step 0: VERIFY GIT REPOSITORY

Run `git rev-parse --is-inside-work-tree`. If not a git repository: **ERROR** — "Not a git repository." Abort.

##### Step 1: CHECK AVAILABILITY

Run the health check script:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/neo4j-health.sh"
```

- If Neo4j is not healthy: **ERROR** — "Neo4j is not available. Run `/forge-admin graph init` to start the graph first." Abort.

##### Step 2: CONFIRM WITH USER

Inform the user what will happen:

"This will delete all project nodes (`ProjectFile`, `ProjectClass`, `ProjectFunction`, `ProjectPackage`, `ProjectDependency`) and rebuild them from the current codebase. The plugin seed graph will not be affected. Bugfix enrichment data (bug_fix_count, last_bug_fix_date) is preserved by default."

Use `AskUserQuestion` to confirm:
- Header: "Graph Rebuild"
- Question: "This will delete all project graph nodes and rebuild them from the current codebase. The plugin seed graph is not affected. Bugfix enrichment is preserved unless --clear-enrichment is specified."
- Options: "Rebuild — delete project nodes and rebuild from codebase (preserves enrichment)" / "Cancel — keep current graph"

###### Component-Scoped Rebuild

Accept optional `--component <name>` argument:
- Without `--component`: rebuild all components for current project
- With `--component api`: rebuild only the `api` component

Deletion is always scoped to current project — never touches other projects' nodes.

###### Enrichment Preservation

By default, `ProjectFile` enrichment properties (`bug_fix_count`, `last_bug_fix_date`) are **preserved** across rebuilds. The deletion step saves enrichment data before deleting, and the rebuild step restores it.

Accept optional `--clear-enrichment` flag to wipe all enrichment data. Useful when enrichment is stale or after significant codebase restructuring.

##### Step 3: RESOLVE PROJECT IDENTITY

Derive the `project_id` for scoping all queries:

```bash
PROJECT_ID=$(git remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||; s|\.git$||')
# Fallback for repos without a remote:
[ -z "$PROJECT_ID" ] && PROJECT_ID=$(basename "$(git rev-parse --show-toplevel)")
```

All Cypher queries in this step MUST include `n.project_id = '$PROJECT_ID'` to avoid affecting other projects sharing the same Neo4j instance.

##### Step 3a: SAVE ENRICHMENT DATA (skip if `--clear-enrichment`)

```bash
echo "MATCH (n:ProjectFile {project_id: '$PROJECT_ID'}) WHERE n.bug_fix_count > 0 RETURN n.path AS path, n.bug_fix_count AS count, n.last_bug_fix_date AS date" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format csv > /tmp/forge-enrichment-backup.csv
```

##### Step 3b: DELETE PROJECT NODES

Delete project-derived nodes **scoped to current project only**:

```bash
echo "MATCH (n) WHERE (n:ProjectFile OR n:ProjectClass OR n:ProjectFunction OR n:ProjectPackage OR n:ProjectDependency) AND n.project_id = '$PROJECT_ID' DETACH DELETE n" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local
```

- If the command exits non-zero: **ERROR** — display the error output. Do not proceed. The graph may be in a partial state — suggest running `/forge-admin graph init` to fully reinitialize.
- If successful: note how many nodes were deleted (cypher-shell reports `Deleted N nodes, deleted M relationships`).

Also clear the stale build marker so the next step always runs:

```bash
rm -f .forge/graph/.last-build-sha
```

##### Step 4: REBUILD PROJECT GRAPH

Re-run the build script and pipe output to Neo4j:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/build-project-graph.sh" --project-root . | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local
```

- If the command exits non-zero: **ERROR** — display the error output and suggest checking that `build-project-graph.sh` is executable and that the project root is correct.
- If successful: write the current commit SHA to `.forge/graph/.last-build-sha`:

```bash
git rev-parse HEAD > .forge/graph/.last-build-sha
```

##### Step 4b: RESTORE ENRICHMENT (skip if `--clear-enrichment`)

If enrichment data was saved in Step 3a and the backup file is non-empty, restore it:

```bash
# Parse the CSV and apply enrichment via MERGE
while IFS=',' read -r path count date; do
  [ -z "$path" ] && continue
  # Escape single quotes in path to prevent Cypher injection
  safe_path=$(printf '%s' "$path" | sed "s/'/''/g")
  echo "MATCH (n:ProjectFile {project_id: '$PROJECT_ID', path: '$safe_path'}) SET n.bug_fix_count = $count, n.last_bug_fix_date = '$date';"
done < /tmp/forge-enrichment-backup.csv | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local
```

- If restoration fails: log WARNING "Enrichment restoration failed — enrichment data lost. Bugfix telemetry will restart from zero." Continue — this is non-blocking.
- Clean up: `rm -f /tmp/forge-enrichment-backup.csv`

##### Step 5: REPORT NEW NODE COUNTS

Query and display the updated node counts:

```bash
echo "MATCH (n) RETURN labels(n)[0] AS label, count(*) AS count ORDER BY count DESC" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain
```

Present a summary:

```
Graph rebuilt successfully.

  Deleted:     142 project nodes, 350 relationships
  Build SHA:   <sha>

  Node counts after rebuild:
    ProjectFile        138
    ProjectClass        41
    ProjectFunction    228
    ProjectPackage      13
    ProjectDependency   27
    _SeedMarker          1    (seed preserved)

  Run /forge-admin graph status for enrichment coverage details.
  Run /forge-admin graph query to explore the graph.
```

If any step failed partway through, clearly indicate the graph may be in an inconsistent state and suggest running `/forge-admin graph init` to fully reinitialize.

#### Action: debug

Targeted diagnostic skill for the Neo4j knowledge graph. Provides structured diagnostic recipes without requiring raw Cypher knowledge.

Read-only. Enforces `LIMIT 50` on every query. All queries scoped to `project_id`.

##### Debug additional prerequisites

- **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
- **Neo4j container running:** Run `shared/graph/neo4j-health.sh`. If unhealthy: report "Neo4j is not available. Run `/forge-admin graph init` first." and STOP.
- **Graph initialized:** Verify graph has nodes (check via node count query). If empty: report "Graph is empty. Run `/forge-admin graph init` to build the project graph." and STOP.

##### Diagnostic Recipes

###### 1. Orphaned Nodes

Nodes with no relationships (potential data quality issue):

```cypher
MATCH (n {project_id: $project_id})
WHERE NOT (n)--()
RETURN labels(n) AS type, count(n) AS count
LIMIT 50
```

###### 2. Stale Nodes

Nodes not updated since the current HEAD:

```cypher
MATCH (n {project_id: $project_id})
WHERE n.last_updated_sha <> $current_sha
RETURN labels(n)[0] AS type, n.name AS name, n.last_updated_sha AS stale_sha
LIMIT 50
```

###### 3. Missing Enrichments

Expected enrichment properties absent on node types:

```cypher
MATCH (n:Function {project_id: $project_id})
WHERE n.complexity IS NULL OR n.test_coverage IS NULL
RETURN n.name AS function, n.file_path AS file
LIMIT 50
```

###### 4. Relationship Integrity

Check for expected relationship types:

```cypher
MATCH (n {project_id: $project_id})
WHERE NOT (n)-[:DEFINED_IN]->()
RETURN labels(n)[0] AS type, n.name AS name
LIMIT 50
```

###### 5. Node Count Summary

Quick health overview by label:

```cypher
MATCH (n {project_id: $project_id})
RETURN labels(n)[0] AS label, count(n) AS count
ORDER BY count DESC
LIMIT 50
```

##### Debug instructions

1. Run Neo4j health check via `shared/graph/neo4j-health.sh`
2. If unhealthy: report status and suggest `/forge-admin graph init` or Docker troubleshooting
3. If healthy: derive `project_id` from git remote origin URL
4. Run diagnostic recipes 1-5, report findings in table format
5. If user provides a specific concern, run targeted Cypher (read-only, enforce LIMIT)
6. Suggest remediation: `/forge-admin graph rebuild` for widespread staleness, manual fixes for isolated issues

##### Debug safety

- All queries are READ-ONLY (no CREATE, MERGE, DELETE, SET)
- All queries enforce LIMIT (max 50 rows default, configurable)
- Never modify graph state -- diagnostic only

#### Graph error handling

Inherits the error-handling tables from each of the five sub-actions. Consolidated matrix:

| Condition | Action |
|---|---|
| Shared prerequisites fail | Report specific error and STOP |
| Docker image pull fails (init) | "Failed to pull Neo4j image. Check internet + Docker Hub access." STOP |
| Neo4j health timeout (60s) | "Neo4j did not become healthy within 60 seconds. Check `docker logs forge-neo4j`." STOP |
| Container not running (status/query/rebuild/debug) | "Neo4j not running. Run `/forge-admin graph init` first." STOP (or show local file data for status) |
| Seed import fails (init) | "Container is running but seed is missing. Retry `/forge-admin graph init`." |
| Query returns no results (query) | "Query returned no results. Check labels with `MATCH (n) RETURN DISTINCT labels(n)`." |
| Non-read-only Cypher passed to query | "Read-only mode: only MATCH queries permitted. Use `/forge-admin graph rebuild` for writes." Exit 2 |
| User cancels rebuild | "Rebuild cancelled. Graph unchanged." STOP |
| Deletion fails mid-rebuild | "Graph may be in partial state. Run `/forge-admin graph init` to fully reinitialize." STOP |
| Enrichment restore fails | WARNING "Bugfix telemetry will restart from zero." Continue |

## Error Handling

| Condition | Action |
|---|---|
| Shared prerequisites fail | Report and STOP |
| Empty area / `-*` first token | Print usage and exit 2 |
| `--help` | Print usage and exit 0 |
| Unknown area | Print "Unknown area" and exit 2 |
| Unknown action within area | Print area-specific usage and exit 2 |
| `graph query` with non-read-only Cypher | Reject with exit 2 (AC-S014) |
| State corruption | `recover diagnose` reports; `recover repair` mutates |

## See Also

- `/forge` — Write-surface entry (run, fix, sprint, review, verify, deploy, commit, migrate, bootstrap, docs, audit)
- `/forge-ask` — Read-only queries (status, history, insights, profile, tour, codebase Q&A)
