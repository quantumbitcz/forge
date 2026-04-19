# ADR-0009: MCP server as read-only interface

- **Status:** Accepted
- **Date:** 2026-04-19
- **Deciders:** @quantumbitcz
- **Supersedes:** —
- **Superseded by:** —

## Context

External AI clients (other agents, IDE integrations, scripts) want to query
`.forge/` artifacts: run history, wiki, explore cache, plan cache, code graph.
Exposing write access would let third-party clients corrupt pipeline state,
invalidating checkpoints and recovery.

## Decision

The MCP server at `shared/mcp-server/` is **read-only**. It exposes 11 query
tools (list runs, fetch wiki pages, ask over explore cache, query code graph,
etc.) but no mutation tools. Writes go only through the pipeline itself.

## Consequences

- **Positive:** State integrity guaranteed; safe to connect untrusted clients; no lock coordination needed across MCP clients.
- **Negative:** Third parties that want to mark learnings "read" or adjust PREEMPT confidence must go through a pipeline run — no ad-hoc updates.
- **Neutral:** If write tools ever become necessary, this ADR gets superseded; the filesystem layout already isolates state.

## Alternatives Considered

- **Option A — Read-write with capability tokens:** Rejected — complexity cost outweighs the use case.
- **Option B — No MCP server, just CLI scripts:** Rejected — loses the "any MCP-capable AI client" story.

## References

- `shared/mcp-server/`
- `shared/mcp-provisioning.md`
