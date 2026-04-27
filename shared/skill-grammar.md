# Skill Invocation Grammar

Canonical grammar for every `skills/*/SKILL.md`. Enforced by
`tests/contract/test_skill_grammar.py`.

## 1. Inspection (read-only) skills → flags only

Skills whose `description:` prefix is `[read-only]` MUST use flags only. No
subcommands. A `## Subcommands` heading in the body is a contract violation.

Current read-only skills: forge-ask, forge-history, forge-insights,
forge-playbooks, forge-profile, forge-security-audit, forge-status, forge-tour,
forge-verify.

## 2. Multi-action (mutating) skills → subcommands only

Skills whose `description:` prefix is `[writes]` and which dispatch multiple
operations MUST use subcommands. Top-level mutually-exclusive flags like
`--build | --config | --all` are forbidden for mutating skills (use subcommand
headings instead). Flags INSIDE a subcommand are fine.

Subcommand skills today: forge-graph (init | rebuild | status | query | debug),
forge-recover (diagnose | repair | reset | resume | rollback | rewind |
list-checkpoints), forge-compress (agents | output | status | help),
forge-handoff (write | list | show | resume | search).

### 2.1 H3 `### Subcommand:` heading wording (read-only skills)

A handful of read-only skills (notably `forge-verify`) carry H3 headings of
the form `### Subcommand: build` even though read-only skills may not use
subcommand semantics (§1). This wording is **tolerated as a legacy artefact**
— the contract test treats the `## Subcommands` H2 heading as the
contract-violating shape; H3 `### Subcommand: <flag>` is read as "per-flag
documentation block" and is grandfathered. New read-only skills SHOULD use
`### Flag: --<name>` instead; existing skills need not be rewritten as part
of Phase 2. (Phase 2 removes `--config` from `forge-verify` for unrelated
reasons; the remaining `### Subcommand: build` and `### Subcommand: all`
headings stay in place and continue to be accepted by the grammar.)

## 3. Positional args

Forbidden except for free-form content:
- Cypher query: `/forge-graph query "MATCH (n) RETURN n"`
- Requirement string: `/forge-run "<requirement>"`, `/forge-fix "<description>"`

Positional mode tokens (`/forge-compress output full`) are a tolerated legacy
form — the grammar neither rejects them nor rewrites them.

## 4. Required body structure for subcommand skills

Every `[writes]` skill that exposes verb-style subcommands MUST include a heading
matching `^## Subcommands?( dispatch)?$` (case-sensitive). Both `## Subcommands`
and `## Subcommand dispatch` are accepted; pick whichever reads naturally for
the skill's prose. The section must list each subcommand with a one-line
purpose and a read-only/writes label. Table or bullet form both accepted.

Examples in current use:
- `## Subcommands` — forge-recover, forge-compress.
- `## Subcommand dispatch` — forge-graph, forge-handoff, forge-review.

## 5. Frontmatter allow-list

Top-level keys permitted in SKILL.md frontmatter:
- `name` (required, string, must match directory)
- `description` (required, string, must start with `[read-only]` or `[writes]`)
- `allowed-tools` (required, list of strings)
- `disable-model-invocation` (optional, bool)
- `ui` (optional, flow- or block-mapping with exactly `{tasks, ask, plan_mode}` as booleans)

Any other top-level key is a contract violation.

## 6. Known tools allow-set

`allowed-tools` values must match one of the names below. Unknown names are a
warning (likely a new tool the grammar doc has not caught up with). Obvious
typos — defined as mixed-case drift (`toolName`, `TOOLNAME`) or Levenshtein
distance ≤ 2 to an allow-set entry — are an error.

Core tools: `Read`, `Edit`, `Write`, `Glob`, `Grep`, `Bash`, `Task`,
`TaskCreate`, `TaskUpdate`, `AskUserQuestion`, `EnterPlanMode`, `ExitPlanMode`,
`Agent`, `WebFetch`, `WebSearch`.

MCP tools: `neo4j-mcp`, `playwright-mcp`, `linear-mcp`, `slack-mcp`,
`context7-mcp`, `figma-mcp`, `excalidraw-mcp`.

Context7 fully-qualified form: `mcp__plugin_context7_context7__resolve-library-id`,
`mcp__plugin_context7_context7__query-docs`. Both permitted.

## 7. Amendment process

Grammar changes follow the same process as `shared/skill-contract.md` §5:
1. Rationale in commit message.
2. Matching update to `tests/contract/test_skill_grammar.py`.
3. Migration of all affected SKILL.md files in the same PR.
