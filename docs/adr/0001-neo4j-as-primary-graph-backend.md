# ADR-0001: Neo4j as primary graph backend

- **Status:** Accepted
- **Date:** 2026-04-19
- **Deciders:** @quantumbitcz
- **Supersedes:** —
- **Superseded by:** —

## Context

The pipeline needs a knowledge graph to store the plugin's seed module relationships
(languages → frameworks → bindings → testing layers) and the consuming project's
codebase graph (symbols, calls, imports, test coverage). Two uses, one store.
Requirements: rich query language (path queries across module boundaries), an MCP
server exposing `neo4j-mcp` to 8+ agents, low operational burden, reproducible
local setup via Docker. Alternatives under consideration: embedded SQLite + a
graph schema, a hosted graph service, plain filesystem JSON.

## Decision

We use Neo4j as the primary graph backend, provisioned via Docker Desktop (Compose
file in `shared/graph/`). Scoping is by `project_id` + optional `component`. Agents
access it through the `neo4j-mcp` MCP server.

## Consequences

- **Positive:** Cypher query power matches the problem shape; MCP server already exists; agents can traverse multi-hop relationships cheaply.
- **Negative:** Docker dependency for users who want graph features; cold-start cost for containers.
- **Neutral:** Requires a fallback for users without Docker (see ADR-0002).

## Alternatives Considered

- **Option A — Embedded SQLite with foreign keys:** Rejected for this primary role because recursive CTEs are a poor fit for the multi-hop queries the pipeline runs. Adopted as the *fallback* in ADR-0002.
- **Option B — Hosted graph service (e.g. Neo4j Aura):** Rejected because the plugin's operating model is local-first; sending project code to a hosted service is out of scope for a doc-only plugin.

## References

- ADR-0002 (SQLite fallback)
- `shared/graph/schema.md`
- `shared/graph/` Docker Compose
