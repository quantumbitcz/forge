---
name: forge-config
description: "Interactive configuration editor for forge.local.md and forge-config.md. Use when changing framework, adding testing, updating scoring thresholds, or toggling features. Validates changes against schema before applying. Trigger: /forge-config, change forge config, update my config"
---

# /forge-config -- Configuration Editor

Interactive editor for Forge project configuration. Validates all changes against the schema before applying.

## Prerequisites

1. **forge.local.md must exist:** Check `.claude/forge.local.md`. If missing: "Run `/forge-init` first." STOP.

## Instructions

### 1. Load current configuration

Read both config files:
- `.claude/forge.local.md` -- static project config (YAML frontmatter)
- `.claude/forge-config.md` -- mutable runtime config (markdown tables)

Parse and display the current values for the section the user wants to edit.

### 2. Present editable sections

Group configuration into categories:

**Core stack:**
- `components.language` -- one of 15 supported languages
- `components.framework` -- one of 21 supported frameworks
- `components.testing` -- one of 19 supported test frameworks
- `components.variant` -- framework variant (optional)

**Commands:**
- `commands.build`, `commands.test`, `commands.lint`, `commands.format`

**Scoring:**
- `critical_weight`, `warning_weight`, `info_weight`
- `pass_threshold`, `concerns_threshold`
- `oscillation_tolerance`, `total_retries_max`

**Convergence:**
- `max_iterations`, `plateau_threshold`, `plateau_patience`, `target_score`

**Features (toggles):**
- `model_routing.enabled`, `output_compression.enabled`, `code_graph.enabled`
- `property_testing.enabled`, `living_specs.enabled`, `confidence.planning_gate`

### 3. Validate changes

Before applying any change:
1. Check value is within PREFLIGHT constraints (see `shared/schemas/forge-config-schema.json`)
2. Check cross-field consistency (e.g., `pass_threshold` > `concerns_threshold` + 10)
3. Report validation result before writing

### 4. Apply changes

Write validated changes to the appropriate config file:
- Stack/commands -> `forge.local.md` (YAML frontmatter)
- Runtime parameters -> `forge-config.md` (markdown tables)

Confirm each change with before/after values.

## Error Handling

| Condition | Action |
|-----------|--------|
| forge.local.md missing | "Run `/forge-init` first." STOP |
| YAML parse failure | Report syntax error location, do not write |
| Value out of range | Report constraint, suggest valid range |
| Unknown config key | Report "Unknown key: {key}. Check docs." |

## See Also

- `/config-validate` -- validate config without editing
- `/forge-init` -- initial project setup
- `/forge-help` -- find the right skill
