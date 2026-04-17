---
name: forge-compress
description: "[writes] Unified compression — `agents` compresses agent .md files for 30-50% system-prompt reduction; `output <mode>` sets runtime output compression (off|lite|full|ultra) writing .forge/caveman-mode; `status` shows current settings (default, read-only); `help` prints reference card. Use to save tokens on prompts or session output. Trigger: /forge-compress, compress agents, compress output, caveman mode, reduce tokens"
---

# Forge Compress

Single entry point for compression. Replaces `/forge-compress` (previous agent-only surface), `/forge-caveman`, and `/forge-compression-help` (all removed in 3.0.0).

## Subcommands

| Subcommand | Read/Write | Purpose |
|---|---|---|
| `agents` | writes | Compress agent `.md` files via terse-rewrite (30–50% reduction) |
| `output <mode>` | writes | Set output compression. mode ∈ {off, lite, full, ultra}. Writes .forge/caveman-mode |
| `status` *(default)* | read-only | Show current agent-compression ratio and output-mode |
| `help` | read-only | Reference card (flags, modes, token savings by mode, tips) |

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: (agents, output) preview without writing
- **--json**: (status, help) structured output

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Examples

```
/forge-compress                            # default: status
/forge-compress output lite                # set lite mode
/forge-compress output ultra --dry-run     # preview ultra without writing
/forge-compress agents                     # compress all agent .md
/forge-compress agents --dry-run           # preview compression
/forge-compress help                       # reference card
/forge-compress status --json              # JSON for scripting
```

## Modes (output subcommand)

| Mode | Token savings | Description |
|------|---------------|-------------|
| off | 0% | Full verbose output (default) |
| lite | ~30% | Strip redundant narration; keep code/data intact |
| full | ~55% | Aggressive prose compression; ellipsis-heavy |
| ultra | ~75% | Caveman grammar; skeletal output only |

Replacements for removed skills:

| Old skill | New invocation |
|---|---|
| /forge-caveman | /forge-compress output <mode> |
| /forge-compression-help | /forge-compress help |
