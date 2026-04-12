---
name: graph-debug
description: "Diagnose Neo4j knowledge graph issues — orphaned nodes, stale data, missing enrichments, relationship integrity. Use when /graph-status shows anomalies, graph queries return unexpected results, or after a failed /graph-rebuild."
---

# Graph Debug

Targeted diagnostic skill for the Neo4j knowledge graph. Provides structured diagnostic recipes without requiring raw Cypher knowledge.

## Prerequisites

- Neo4j container running (check via `shared/graph/neo4j-health.sh`)
- Graph initialized (`/graph-init` completed)

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

## Procedure

1. Run Neo4j health check via `shared/graph/neo4j-health.sh`
2. If unhealthy: report status and suggest `/graph-init` or Docker troubleshooting
3. If healthy: derive `project_id` from git remote origin URL
4. Run diagnostic recipes 1-5, report findings in table format
5. If user provides a specific concern, run targeted Cypher (read-only, enforce LIMIT)
6. Suggest remediation: `/graph-rebuild` for widespread staleness, manual fixes for isolated issues

## Safety

- All queries are READ-ONLY (no CREATE, MERGE, DELETE, SET)
- All queries enforce LIMIT (max 50 rows default, configurable)
- Never modify graph state — diagnostic only
