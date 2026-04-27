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

## 4. Skill categorization (Phase 5 baseline — 28 skills)

**Read-only (9):** forge-ask, forge-history, forge-insights, forge-playbooks, forge-profile, forge-security-audit, forge-status, forge-tour, forge-verify (plus any subcommand of `/forge-graph` marked read-only — but the parent skill is classified by maximum impact per §1).

**Writes (19):** forge-abort, forge-automation, forge-bootstrap, forge-commit, forge-compress, forge-config, forge-deploy, forge-docs-generate, forge-fix, forge-graph, forge-handoff, forge-init, forge-migration, forge-playbook-refine, forge-recover, forge-review, forge-run, forge-shape, forge-sprint.

**Total: 28.** `/forge-graph` is `[writes]` (its `init` and `rebuild` subcommands write) even though `status`, `query`, and `debug` are read-only — the badge reflects maximum impact per §1.

## 5. Amendment process

This contract is versioned with the plugin. Amendments require:
1. A rationale in the commit message describing the change
2. A matching update to `tests/contract/skill-contract.bats`
3. Migration of all affected SKILL.md files in the same PR

## 6. Grammar contract

Invocation grammar (flags vs subcommands vs positional content) is enforced by
`tests/contract/skill_grammar.py` against the rules in `shared/skill-grammar.md`.
Every SKILL.md frontmatter is validated against a strict pydantic model: only
the keys `name`, `description`, `allowed-tools`, `disable-model-invocation`,
and `ui` are permitted at the top level.
