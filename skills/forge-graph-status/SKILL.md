---
name: forge-graph-status
description: "Show Neo4j knowledge graph status -- node counts, container health, last build SHA, enrichment coverage. Use when you want to check if the graph is healthy, see what data is indexed, or verify the graph is up to date with the latest code changes."
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']
---

# /forge-graph-status — Knowledge Graph Status

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. **Neo4j available:** Check Docker container running. If not: report "Neo4j not running. Run /forge-graph-init first." and STOP.

You are the graph status reporter. Your job is to display the current state of the Neo4j knowledge graph: container health, node and relationship counts, last build SHA, and enrichment coverage.

## Container Name Resolution

Before starting, resolve the Neo4j container name: read `graph.neo4j_container_name` from `.claude/forge.local.md`. If not set, use default `forge-neo4j`. Use the resolved name in ALL `docker` commands below.

## Instructions

---

### Step 1: CONTAINER HEALTH

Run the health check script:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/neo4j-health.sh"
```

- If exit 0: container is healthy — note status as **HEALTHY**.
- If non-zero: container is not responding — note status as **UNAVAILABLE** and show the error output.

Also check the container's running state:

```bash
docker ps --filter "name=forge-neo4j" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

If Docker itself is unavailable, report: "Docker is not available. Cannot check graph status."

---

### Per-Project Node Counts

Show node counts grouped by project:
```cypher
MATCH (n) WHERE n.project_id IS NOT NULL
RETURN n.project_id, labels(n)[0] AS label, count(n) AS count
ORDER BY n.project_id, label
```

---

### Step 2: NODE COUNTS

If Neo4j is healthy, query node counts by label:

```bash
echo "MATCH (n) RETURN labels(n)[0] AS label, count(*) AS count ORDER BY count DESC" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain
```

Display all results in a table.

---

### Step 3: LAST BUILD SHA

Read `.forge/graph/.last-build-sha` and display its contents.

- If the file does not exist: show "No build recorded yet."
- If the file exists: also compare to `git rev-parse HEAD` and indicate whether the graph is **up to date** or **stale** (HEAD has moved since last build).

---

### Step 4: ENRICHMENT COVERAGE

Read `.forge/graph/.enriched-files` if it exists.

- Show total number of enriched files.
- Show percentage of project source files covered (compare to total files tracked by git: `git ls-files | wc -l`).
- If the file does not exist: show "No enrichment data recorded."

---

### Step 5: RELATIONSHIP COUNTS

If Neo4j is healthy, query relationship counts:

```bash
echo "MATCH ()-[r]->() RETURN type(r) AS type, count(*) AS count ORDER BY count DESC" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain
```

Display all results in a table.

---

### Step 6: REPORT

Present a consolidated status summary:

```
Knowledge Graph Status

  Container:         HEALTHY (forge-neo4j)
  Ports:             7474 (HTTP), 7687 (Bolt)

  Last build:        abc1234  (up to date)

  Node counts:
    ProjectFile        142
    ProjectClass        38
    ProjectFunction    215
    ProjectPackage      12
    ProjectDependency   27
    _SeedMarker          1

  Relationship counts:
    CONTAINS           180
    CALLS               94
    IMPORTS             61
    DEPENDS_ON          27

  Enrichment coverage: 89/142 files (63%)

  Run /forge-graph-init to rebuild if stale.
  Run /forge-graph-query <cypher> to explore.
```

If Neo4j is unavailable, show what can be determined from local files (last build SHA, enriched files) and suggest running `/forge-graph-init`.

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| Docker not available | Report "Docker is not available. Cannot check graph status." Show local file data only |
| Neo4j container not running | Report "Neo4j not running. Run `/forge-graph-init` first." Show local file data if available |
| Neo4j unhealthy | Report container status as UNAVAILABLE with error output. Show local file data |
| Cypher query fails | Report the error. Suggest checking container logs with `docker logs forge-neo4j` |
| .last-build-sha missing | Report "No build recorded yet." |
| .enriched-files missing | Report "No enrichment data recorded." |

## See Also

- `/forge-graph-init` -- Initialize or restart the graph if status shows it is unavailable
- `/forge-graph-rebuild` -- Rebuild the graph if status shows stale data
- `/forge-graph-debug` -- Diagnose specific graph issues (orphaned nodes, missing enrichments)
- `/forge-graph-query` -- Run Cypher queries to explore graph data
