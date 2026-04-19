# Architecture Decision Records

This directory records the major architectural decisions that shape `forge`.
Decisions are immutable: reversing one means adding a new ADR that *supersedes*
the old one. History is additive.

## Status legend

- **Proposed** — under discussion, not yet merged
- **Accepted** — merged to `master` and currently in effect
- **Superseded by ADR-NNNN** — no longer in effect; replaced
- **Deprecated** — no longer in effect; not replaced

## Numbering

Four-digit, zero-padded, dense. Gaps are forbidden. Superseded ADRs are never
renumbered. Filename rule: `NNNN-kebab-case-title.md`; the `# ADR-NNNN:` title
inside the file matches the filename stem.

## Index

| # | Title | Status | Date |
|---|-------|--------|------|
| 0001 | [Neo4j as primary graph backend](0001-neo4j-as-primary-graph-backend.md) | Accepted | 2026-04-19 |
| 0002 | [SQLite + tree-sitter fallback](0002-sqlite-tree-sitter-fallback.md) | Accepted | 2026-04-19 |
| 0003 | [Deterministic FSM for state transitions](0003-deterministic-fsm-state-transitions.md) | Accepted | 2026-04-19 |
| 0004 | [Evidence-based shipping gate](0004-evidence-based-shipping-gate.md) | Accepted | 2026-04-19 |
| 0005 | [Composition precedence ordering](0005-composition-precedence-ordering.md) | Accepted | 2026-04-19 |
| 0006 | [87-category scoring model](0006-87-category-scoring-model.md) | Accepted | 2026-04-19 |
| 0007 | [Bash-to-Python tooling migration](0007-bash-to-python-tooling-migration.md) | Accepted | 2026-04-19 |
| 0008 | [No backwards compatibility stance](0008-no-backwards-compatibility-stance.md) | Accepted | 2026-04-19 |
| 0009 | [MCP server as read-only interface](0009-mcp-server-as-read-only-interface.md) | Accepted | 2026-04-19 |
| 0010 | [Worktree isolation for parallel runs](0010-worktree-isolation-for-parallel-runs.md) | Accepted | 2026-04-19 |
| 0011 | [Output compression levels](0011-output-compression-levels.md) | Accepted | 2026-04-19 |

## Writing a new ADR

1. Copy `_template.md` to `NNNN-kebab-case-title.md` with the next free number.
2. Fill in Context, Decision, Consequences, Alternatives Considered, References.
3. Set `Status: Proposed` while the PR is open.
4. On merge, flip to `Status: Accepted` and add a row to the Index table above.
