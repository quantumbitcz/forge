---
name: forge-caveman
description: "Toggle caveman-style terse output for Forge pipeline messages. Use when you want to reduce user-facing output tokens by 40-70% while preserving technical substance. Trigger: /forge-caveman [mode], caveman mode, less tokens, be brief"
---

# /forge-caveman -- Terse Output Mode

Toggle caveman-style terse output for Forge pipeline messages. Reduces user-facing output tokens by 40-70% while preserving all technical substance.

## Prerequisites

None. Works in any project.

## Instructions

### 1. Parse mode argument

Accept one of:
- `full` -- normal verbose output (default)
- `terse` -- drop filler, keep structure
- `caveman` -- maximum compression, telegraphic style
- No argument -- toggle between `full` and `caveman`

### 2. Apply mode

Write the selected mode to `.forge/output-mode.json`:

```json
{
  "mode": "caveman",
  "set_at": "2025-01-15T10:30:00Z"
}
```

### 3. Confirm

Report the active mode to the user:

```
Output mode: caveman (40-70% fewer tokens)
```

## Error Handling

| Condition | Action |
|-----------|--------|
| Invalid mode argument | Default to `full` |
| `.forge/` directory missing | Create it |

## See Also

- `/forge-compress` -- compress input files (agent prompts, convention stacks)
- `/forge-help` -- find the right skill for your situation
