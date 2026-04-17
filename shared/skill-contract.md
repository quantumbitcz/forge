# Skill Contract

Authoritative specification for every `skills/*/SKILL.md` in this plugin.
Enforced by `tests/contract/skill-contract.bats`.

## 1. Frontmatter description prefix

The first token of `description:` in YAML frontmatter MUST be exactly one of:

- `[read-only]` — skill never modifies any file under `.forge/`, `.claude/`, or project source
- `[writes]` — skill may modify state, source, or caches

Badge reflects **maximum impact** — if any subcommand of the skill can write, the skill is `[writes]` even when the default subcommand is read-only.

## 2. Required sections in SKILL.md body

### `## Flags`

One bullet per flag, syntax `- **--flag**: <description>`.

All skills MUST list:
- `--help` — print usage (description + flags + 3 examples + exit codes) and exit 0

Mutating skills additionally MUST list:
- `--dry-run` — preview actions without writing. Implementation: skill sets `FORGE_DRY_RUN=1` env var; downstream agents honour it

Read-only skills additionally MUST list:
- `--json` — emit structured JSON to stdout, suppressing human-readable prose

### `## Exit codes`

Either inline list OR a single line: `See shared/skill-contract.md for the standard exit-code table.`

## 3. Standard exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | User error (bad args, missing config, unknown subcommand) |
| 2 | Pipeline failure (agent reported FAIL or CONCERNS without override) |
| 3 | Recovery needed (state corruption, locked, or escalated) |
| 4 | Aborted by user (`/forge-abort`, Ctrl+C, or "Abort" chosen in `AskUserQuestion`) |

## 4. Skill categorization (Phase 1 baseline — 35 skills)

**Read-only (15):** forge-ask, forge-codebase-health, forge-config-validate, forge-graph-debug, forge-graph-query, forge-graph-status, forge-help, forge-history, forge-insights, forge-playbooks, forge-profile, forge-security-audit, forge-status, forge-tour, forge-verify.

**Writes (20):** forge-abort, forge-automation, forge-bootstrap, forge-commit, forge-compress, forge-config, forge-deep-health, forge-deploy, forge-docs-generate, forge-fix, forge-graph-init, forge-graph-rebuild, forge-init, forge-migration, forge-playbook-refine, forge-recover, forge-review, forge-run, forge-shape, forge-sprint.

## 5. Amendment process

This contract is versioned with the plugin. Amendments require:
1. A spec in `docs/superpowers/specs/` describing the change
2. A matching update to `tests/contract/skill-contract.bats`
3. Migration of all affected SKILL.md files in the same PR
