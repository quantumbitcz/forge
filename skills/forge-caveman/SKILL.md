---
name: forge-caveman
description: "Toggle terse output for Forge pipeline messages. Reduces prose by 40-70% per message (4-10% total session token savings). Use when you want briefer output. Trigger: /forge-caveman [mode], caveman mode, less tokens, be brief"
allowed-tools: ['Read', 'Write', 'Edit', 'Bash']
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

## Natural Language Triggers

These phrases are guidance for the LLM to recognize user intent -- they are NOT routing enforcement. The LLM may interpret these as requests to activate caveman mode, but matching is best-effort:

- "caveman mode", "go caveman", "caveman on"
- "less tokens", "fewer tokens", "reduce output"
- "be brief", "be terse", "be concise"
- "shorter replies", "compress output"
- "stop caveman", "normal mode", "verbose again"

These phrases help the LLM understand intent. They do not trigger deterministic routing.

## Instructions

1. Parse argument from `$ARGUMENTS`:
   - Empty or "full" → mode = `full`
   - "lite" → mode = `lite`
   - "ultra" → mode = `ultra`
   - "off", "stop", "normal" → mode = `off`
   - "status" → check current mode and report (see step 2a)
   - "benchmark" or "bench" → run benchmark (see step 5)
2. **Check current status first:**
   - Read `.forge/caveman-mode` if it exists
   - If the requested mode matches the current mode, report: "Caveman {mode} already active." and STOP (no re-write needed)
   - 2a. If argument is "status": report current mode and STOP
3. Write mode to `.forge/caveman-mode` (single line: `off`, `lite`, `full`, `ultra`)
   - If `.forge/` does not exist, create it
4. Confirm to user with savings estimate:
   - `off`: "Caveman mode off. Normal output."
   - `lite`: "Caveman lite active. Drop filler, keep grammar. (~20% prose reduction, ~2-4% session savings)"
   - `full`: "Caveman on. [thing] [action] [reason]. [next step]. (~45% prose reduction, ~4-7% session savings)"
   - `ultra`: "CAVEMAN ULTRA. Max compress. Abbrev all. (~65% prose reduction, ~7-10% session savings)"
5. **Benchmark mode** (if argument is "benchmark" or "bench"):
   - Run `bash "${CLAUDE_PLUGIN_ROOT}/shared/caveman-benchmark.sh" [file]`
   - If user provided a file argument after "benchmark" (e.g., `/forge-caveman benchmark agents/fg-100-orchestrator.md`), pass it to the script
   - If no file argument, the script uses `.forge/forge-log.md` as default sample
   - Display the output table to the user
   - Do NOT change the current caveman mode

## Auto-Clarity Exceptions

Compression suspends automatically for:
- Security warnings (`SEC-*` CRITICAL findings)
- Irreversible action confirmations
- `AskUserQuestion` content
- Escalation messages (convergence failure, budget exhaustion)
- PR descriptions
- Error diagnostics (`BUILD_FAILURE`/`TEST_FAILURE`/`LINT_FAILURE` destined for user)

After the excepted block, caveman mode resumes.

## Research Backing

Brevity constraints improve LLM accuracy by up to 26pp (arXiv:2604.00025, March 2026). The 6-line prompt finding confirms that lite/full/ultra rule blocks (5-10 lines each) are in the effective range for compression instruction. Realistic total session savings are 4-10% (not 45-65%, which is prose-only). Auto-clarity exceptions for security, irreversible actions, and user-facing content are validated as critical by the paper.

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

## Auto-Activation via SessionStart Hook

Caveman mode can activate automatically at the start of every session without requiring `/forge-caveman` each time.

### Configuration

In `.claude/forge-config.md`:

```yaml
caveman:
  enabled: true
  default_mode: lite    # lite | full | ultra
```

### Behavior

When `caveman.enabled: true` in config:
1. The `SessionStart` hook checks for `.forge/caveman-mode`
2. If the file is missing, the hook creates it with the `default_mode` value
3. If the file exists, the hook reads the current mode (preserving manual overrides)
4. The hook emits compression instructions for the active mode

This allows set-and-forget configuration: enable once in `forge-config.md`, and every session starts in caveman mode. Manual `/forge-caveman [mode]` overrides persist until the file is deleted.

### Disabling

- Set `caveman.enabled: false` (or omit the section) to disable auto-activation
- Run `/forge-caveman off` to disable for the current session while keeping auto-activation for future sessions
- Delete `.forge/caveman-mode` to reset to config defaults on next session

## See Also

- `/forge-compress` -- compress input files (agent prompts, convention stacks)
- `/forge-compression-help` -- quick reference card for all compression features
- `/forge-commit` -- terse conventional commit messages
- `/forge-help` -- find the right skill for your situation
- See `benchmarks/` for compression measurements (if available)
