# Graph Migrations

Each file in this directory is a Cypher migration script that upgrades the Neo4j graph schema.

## Format

- Filename: `NNN-description.cypher` (zero-padded sequence number)
- Content: Idempotent Cypher statements
- Must include a version bump via `SchemaVersion` node

## Running Migrations

Migrations are applied at PREFLIGHT by the orchestrator when a version mismatch is detected.
They execute in numerical order via `cypher-shell` or the Neo4j MCP.

## Adding a New Migration

1. Copy the template below
2. Set the sequence number to the next available number
3. Update `shared/graph/schema.md` version header to match

Template:
```cypher
// Migration NNN: description
// Idempotent — safe to re-run

// ... your Cypher statements ...

// Bump version
MERGE (v:SchemaVersion {project_id: $project_id})
SET v.version = '1.N', v.updated_at = datetime();
```
