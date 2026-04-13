---
name: forge-caveman
description: "Toggle caveman-style terse output for Forge pipeline messages. Use when you want to reduce user-facing output tokens by 40-70% while preserving technical substance. Trigger: /forge-caveman [mode], caveman mode, less tokens, be brief"
disable-model-invocation: true
---

# Forge Caveman Mode

Toggle user-facing output compression. Does NOT affect inter-agent communication (controlled by `output_compression.*` config).

## Modes

| Mode | Trigger | Behavior |
|------|---------|----------|
| `lite` | `/forge-caveman lite` | Drop filler/hedging, keep grammar and articles |
| `full` | `/forge-caveman` or `/forge-caveman full` | Default. Drop articles, fragments OK, short synonyms |
| `ultra` | `/forge-caveman ultra` | Abbreviate everything (DB, auth, req/res, impl, config), arrows for causality, no conjunctions |
| `off` | `/forge-caveman off` or "stop caveman" or "normal mode" | Standard verbose output |

## Instructions

1. Parse argument from `$ARGUMENTS`:
   - Empty or "full" → mode = `full`
   - "lite" → mode = `lite`
   - "ultra" → mode = `ultra`
   - "off", "stop", "normal" → mode = `off`
2. Write mode to `.forge/caveman-mode` (single line: `off`, `lite`, `full`, `ultra`)
   - If `.forge/` does not exist, create it
3. Confirm to user:
   - `off`: "Caveman mode off. Normal output."
   - `lite`: "Caveman lite active. Drop filler, keep grammar."
   - `full`: "Caveman on. [thing] [action] [reason]. [next step]."
   - `ultra`: "CAVEMAN ULTRA. Max compress. Abbrev all."

## Auto-Clarity Exceptions

Compression suspends automatically for:
- Security warnings (`SEC-*` CRITICAL findings)
- Irreversible action confirmations
- `AskUserQuestion` content
- Escalation messages (convergence failure, budget exhaustion)
- PR descriptions

After the excepted block, caveman mode resumes.

## Output Patterns

### Lite
```
Drop filler/hedging. Keep articles and full sentences.
"The review found 2 critical issues and 3 warnings. Score is 75."
```

### Full (default)
```
Pattern: [thing] [action] [reason]. [next step].

BEFORE: "I've completed the review of your authentication module. The quality
         gate found 2 critical issues and 3 warnings. The score is 75, which
         falls in the CONCERNS range. Let me explain the findings..."

AFTER:  "Review done. Score 75 (CONCERNS). 2 CRITICAL, 3 WARNING.
         Findings:"
```

### Ultra
```
Abbreviate: DB, auth, req/res, impl, config, fn, var, dep, pkg.
Arrows: cause → effect. No conjunctions.

BEFORE: "Review done. Score 75 (CONCERNS). 2 CRITICAL, 3 WARNING."
AFTER:  "Rev: 75/CONCERNS. 2C 3W."
```

## Prerequisites

None. Works in any project.

## Error Handling

| Condition | Action |
|-----------|--------|
| Invalid mode argument | Default to `full` |
| `.forge/` directory missing | Create it |

## Persistence

- Mode persists in `.forge/caveman-mode` across pipeline runs
- Orchestrator reads at PREFLIGHT and applies to user-facing messages
- `.forge/caveman-mode` survives `/forge-reset`

## See Also

- `/forge-compress` — compress input files (agent prompts, convention stacks)
- `/forge-help` — find the right skill for your situation
