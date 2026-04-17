---
name: forge-config
description: "[writes] Edit Forge pipeline settings interactively. Use when changing framework, test runner, scoring thresholds, reviewer selection, convergence limits, or toggling features like caveman mode. Validates changes. Trigger: /forge-config, change settings, edit config, adjust thresholds, update scoring"
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'AskUserQuestion']
ui: { ask: true }
disable-model-invocation: false
---

# Forge Config — Interactive Configuration Editor

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: preview actions without writing

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Operations

| Command | Action |
|---------|--------|
| `/forge-config` | Show current config summary |
| `/forge-config set <key> <value>` | Set a config value |
| `/forge-config add <key> <value>` | Add to list field (e.g., code_quality) |
| `/forge-config remove <key> <value>` | Remove from list field |
| `/forge-config validate` | Run validation (delegates to /forge-config-validate) |
| `/forge-config show <section>` | Show specific section (components, scoring, convergence, caveman) |
| `/forge-config diff` | Show changes since last pipeline run |

## Prerequisites

1. Verify `.claude/forge.local.md` or `.claude/forge-config.md` exists. If neither: "No forge configuration found. Run `/forge-init` first." STOP.

## Instructions

### Show (default, no arguments)

1. Read `.claude/forge.local.md` and `.claude/forge-config.md`
2. Display summary: components, scoring thresholds, convergence settings, enabled features
3. Highlight any validation warnings

### Set Operation

1. Parse key path and new value from `$ARGUMENTS` (e.g., `set components.testing vitest`)
2. Run `${CLAUDE_PLUGIN_ROOT}/shared/validate-config.sh` with the proposed change
3. If ERROR: show error message with suggestion, do NOT apply
4. If WARNING: show warning and ask user to confirm
5. If PASS: apply change to appropriate file
   - `components.*` → `forge.local.md`
   - `scoring.*`, `convergence.*`, `caveman.*` → `forge-config.md`
6. Show before/after diff

### Add / Remove Operations

1. Parse key and value from `$ARGUMENTS`
2. Verify key is a list field (e.g., `code_quality`)
3. For `add`: append value if not already present
4. For `remove`: delete value if present, warn if not found
5. Validate after change

### Validate Operation

Delegates to `/forge-config-validate` skill. Shows results inline.

### Diff Operation

1. Read current config from `forge.local.md` and `forge-config.md`
2. Read last pipeline state from `.forge/state.json` (if exists)
3. Show fields that changed since last run
4. If no `.forge/state.json`: show "No previous run to compare against"

## Safeguards

- **Locked sections:** `<!-- locked -->` fences in `forge-config.md` cannot be modified. Show: "This value is locked. Remove the <!-- locked --> fence to unlock."
- **Auto-tuned values:** Values previously modified by retrospective (fg-700) show warning: "This value was auto-tuned by the pipeline. Override? [y/n]"
- **Always validate:** Every `set`/`add`/`remove` operation runs validation before applying
- **Show diff:** Always show before/after diff before applying changes

## Error Handling

| Condition | Action |
|-----------|--------|
| Config file missing | Suggest: "Run /forge-init first" |
| Invalid key path | Show valid keys from config-schema.json |
| Invalid value | Show valid values with fuzzy suggestion |
| Locked section | Refuse edit, explain how to unlock |

## See Also

- `/forge-config-validate` — validate config without editing
- `/forge-init` — initial project setup
- `/forge-help` — find the right skill
