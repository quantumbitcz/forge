---
name: forge-compression-help
description: "Quick reference card for all Forge compression features -- output modes, inter-agent compression, input compression, and configuration. Use when you need a reminder of compression options or want to understand how compression works."
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']
disable-model-invocation: true
---

# Forge Compression -- Quick Reference Card

## Prerequisites

None. This skill is a reference guide.

## Instructions

Display the reference card below. If the user asks about a specific section, navigate directly to it.

## Error Handling

None. This skill displays static content.

---

## 1. User-Facing Output Compression (Caveman Mode)

Controls how Forge talks to YOU. Does not affect inter-agent communication.

| Mode | Command | Effect | Estimated Savings |
|------|---------|--------|-------------------|
| Off | `/forge-caveman off` | Standard verbose output | 0% |
| Lite | `/forge-caveman lite` | Drop filler/hedging, keep grammar | ~20% |
| Full | `/forge-caveman` | Fragments OK, short synonyms, drop articles | ~45% |
| Ultra | `/forge-caveman ultra` | Max abbreviation, arrows, no conjunctions | ~65% |

**Auto-clarity exceptions:** Security warnings, irreversible confirmations, `AskUserQuestion`, escalations, and PR descriptions always use full verbosity regardless of mode.

**Persistence:** Stored in `.forge/caveman-mode`. Survives `/forge-reset`.

## 2. Inter-Agent Output Compression

Controls how agents talk to EACH OTHER inside the pipeline. Configured in `forge-config.md`.

| Level | Name | Token Range | Savings | Default Stages |
|-------|------|-------------|---------|----------------|
| 0 | `verbose` | 800-2000 | 0% | User reports, escalations |
| 1 | `standard` | 800-2000 | ~20% | Planning, docs, retrospective |
| 2 | `terse` | 400-1200 | ~45% | Implementation, verification, review |
| 3 | `minimal` | 100-600 | ~65% | Inner-loop lint/test, mutation, scaffolding |

**Configuration:**
```yaml
output_compression:
  enabled: true
  default_level: terse
  auto_clarity: true
  per_stage:
    PREFLIGHT: standard
    EXPLORING: standard
    PLANNING: standard
    VALIDATING: terse
    IMPLEMENTING: terse
    VERIFYING: terse
    REVIEWING: terse
    DOCUMENTING: standard
    SHIPPING: verbose
    LEARNING: standard
```

## 3. Input Compression (Agent Prompt Reduction)

Reduces token cost of agent `.md` system prompts. Applied offline, not at runtime.

| Command | What It Does |
|---------|-------------|
| `/forge-compress` | Compress agent prompts (default: `agents/` scope) |
| `/forge-compress --dry-run` | Estimate savings without modifying files |
| `/forge-compress --restore` | Restore original files from `.original.md` backups |
| `/forge-compress --scope all` | Compress agents + modules + shared + config |
| `/forge-compress --level 1` | Conservative (~20% reduction) |
| `/forge-compress --level 2` | Aggressive (~45% reduction) |
| `/forge-compress --level 3` | Ultra (~65% reduction) |

**Rules:** Preserves frontmatter, code blocks, tables, technical terms, category codes, severity levels, and all numeric thresholds. Compresses prose only.

## 4. Related Skills

| Skill | Purpose |
|-------|---------|
| `/forge-caveman` | Toggle user-facing output compression |
| `/forge-compress` | Compress input files (agent prompts) |
| `/forge-commit` | Terse conventional commit messages |
| `/forge-review` | Review with optional terse output format |
| `/forge-help` | Find the right skill |

## 5. Configuration Summary

All compression settings in `forge-config.md`:

```yaml
# User-facing output (caveman mode)
caveman:
  enabled: true           # Auto-activate via SessionStart hook
  default_mode: full      # lite | full | ultra

# Inter-agent output compression
output_compression:
  enabled: true
  default_level: terse    # verbose | standard | terse | minimal
  auto_clarity: true      # Suspend compression for security/escalation
  per_stage: { ... }      # Per-stage overrides (see section 2)

# Input compression (agent prompts)
# No config -- controlled via /forge-compress flags
```

## See Also

- Output compression spec — see `output-compression.md` in `shared`
- Input compression rules — see `input-compression.md` in `shared`
- `benchmarks/` -- compression measurements (if available)
