# ADR-0002: SQLite + tree-sitter fallback

- **Status:** Accepted
- **Date:** 2026-04-19
- **Deciders:** @quantumbitcz
- **Supersedes:** —
- **Superseded by:** —

## Context

ADR-0001 establishes Neo4j as primary but requires Docker. A material share of
users (CI runners, restricted environments, evaluators) cannot run Docker. We
need a zero-dependency alternative that still answers the core questions
(symbols, calls, imports, file relationships) without demanding Cypher power.

## Decision

We ship a SQLite-backed code graph built by `shared/graph/build-code-graph.sh`
using tree-sitter for language parsing. Schema: 15 node types, 17 edge types,
all 15 supported languages. Stored at `.forge/code-graph.db`. Config flags:
`code_graph.enabled` (default true), `code_graph.backend` (`auto`/`sqlite`/`neo4j`).
`auto` selects `sqlite` unless Neo4j is reachable.

## Consequences

- **Positive:** Zero external dependencies beyond a checked-in binary. Works on every supported platform. Survives `/forge-recover reset`.
- **Negative:** Cypher-class traversal queries are not available; the MCP server exposes a narrower tool surface over SQLite.
- **Neutral:** Two graph code paths to maintain, partially unified by the `code_graph.backend` switch.

## Alternatives Considered

- **Option A — Make Neo4j required:** Rejected because it would block evaluators and lightweight CI runners, a non-trivial fraction of the audience.
- **Option B — File-per-symbol JSON index:** Rejected because `Edit/Grep` on thousands of small files is slower than a single SQLite query and we already embed SQLite for `run-history.db`.

## References

- ADR-0001 (Neo4j primary)
- `shared/graph/code-graph-schema.sql`
- `shared/graph/build-code-graph.sh`
