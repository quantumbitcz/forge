---
name: forge-graph-debug
description: "Diagnose Neo4j knowledge graph issues — orphaned nodes, stale data, missing enrichments, relationship integrity. Use when /graph-status shows anomalies, graph queries return unexpected results, or after a failed /graph-rebuild."
---

# /forge-graph-debug -- Graph Debug

Targeted diagnostic skill for the Neo4j knowledge graph. Provides structured diagnostic recipes without requiring raw Cypher knowledge.

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Neo4j container running:** Run `shared/graph/neo4j-health.sh`. If unhealthy: report "Neo4j is not available. Run `/graph-init` first." and STOP.
3. **Graph initialized:** Verify graph has nodes (check via node count query). If empty: report "Graph is empty. Run `/graph-init` to build the project graph." and STOP.

## Diagnostic Recipes

### 1. Orphaned Nodes

Nodes with no relationships (potential data quality issue):

```cypher
MATCH (n {project_id: $project_id})
WHERE NOT (n)--()
RETURN labels(n) AS type, count(n) AS count
LIMIT 50
```

### 2. Stale Nodes

Nodes not updated since the current HEAD:

```cypher
MATCH (n {project_id: $project_id})
WHERE n.last_updated_sha <> $current_sha
RETURN labels(n)[0] AS type, n.name AS name, n.last_updated_sha AS stale_sha
LIMIT 50
```

### 3. Missing Enrichments

Expected enrichment properties absent on node types:

```cypher
MATCH (n:Function {project_id: $project_id})
WHERE n.complexity IS NULL OR n.test_coverage IS NULL
RETURN n.name AS function, n.file_path AS file
LIMIT 50
```

### 4. Relationship Integrity

Check for expected relationship types:

```cypher
MATCH (n {project_id: $project_id})
WHERE NOT (n)-[:DEFINED_IN]->()
RETURN labels(n)[0] AS type, n.name AS name
LIMIT 50
```

### 5. Node Count Summary

Quick health overview by label:

```cypher
MATCH (n {project_id: $project_id})
RETURN labels(n)[0] AS label, count(n) AS count
ORDER BY count DESC
LIMIT 50
```

## Instructions

1. Run Neo4j health check via `shared/graph/neo4j-health.sh`
2. If unhealthy: report status and suggest `/graph-init` or Docker troubleshooting
3. If healthy: derive `project_id` from git remote origin URL
4. Run diagnostic recipes 1-5, report findings in table format
5. If user provides a specific concern, run targeted Cypher (read-only, enforce LIMIT)
6. Suggest remediation: `/graph-rebuild` for widespread staleness, manual fixes for isolated issues

## Safety

- All queries are READ-ONLY (no CREATE, MERGE, DELETE, SET)
- All queries enforce LIMIT (max 50 rows default, configurable)
- Never modify graph state -- diagnostic only

## Error Handling

| Condition | Action |
|-----------|--------|
| Neo4j container not running | Report status and suggest `/graph-init` or Docker troubleshooting |
| Neo4j unhealthy | Report error output. Suggest checking container logs |
| Cypher query fails | Display error output. Suggest `/graph-init` if persistent |
| No project_id derivable (no git remote) | Fall back to basename of project root |
| Query returns too many rows | Enforce LIMIT (max 50 default). Suggest narrowing the diagnostic |

## See Also

- `/graph-status` -- Quick overview of graph health and node counts
- `/graph-rebuild` -- Rebuild the graph when debug shows widespread staleness or corruption
- `/graph-init` -- Full initialization when the container is not running
- `/graph-query` -- Run custom Cypher queries for deeper investigation
