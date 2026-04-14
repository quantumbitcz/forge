# Graph Schema Versioning

## Current Version: 1.0

The graph schema version is stored as a Neo4j graph property:

```cypher
MERGE (v:SchemaVersion {project_id: $project_id})
SET v.version = '1.0', v.updated_at = datetime()
```

## Version Check

At PREFLIGHT, the orchestrator (fg-100-orchestrator) checks the graph schema version:

1. Query: `MATCH (v:SchemaVersion {project_id: $pid}) RETURN v.version`
2. Compare against expected version in `shared/graph/schema.md` header
3. If version mismatch:
   - Minor version (1.0 to 1.1): Run incremental migration
   - Major version (1.x to 2.0): Recommend `/forge-graph-rebuild`
   - No version found: Assume 1.0 (backward compatible)

## Migration Scripts

Migrations live in `shared/graph/migrations/`:

```
shared/graph/migrations/
  001-add-schema-version.cypher    # Initial version tracking
  README.md                        # How to add a migration
```

Each migration file:
- Named `NNN-description.cypher`
- Contains idempotent Cypher statements
- Includes a version bump: `SET v.version = '1.N'`

## Adding a New Migration

1. Create `shared/graph/migrations/NNN-description.cypher`
2. Update expected version in `shared/graph/schema.md` header
3. Add migration to `shared/graph/migrations/README.md`
4. Test: `/forge-graph-rebuild` should produce same result as fresh build + migrations

## SQLite Code Graph Versioning

The SQLite code graph (`shared/graph/code-graph-schema.sql`) includes a version table:

```sql
CREATE TABLE IF NOT EXISTS schema_version (
  version TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

Migration scripts for SQLite live alongside the `.sql` schema file.
