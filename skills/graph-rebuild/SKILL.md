---
name: graph-rebuild
description: Rebuild the project codebase graph from scratch. Keeps the plugin seed graph intact. Use when incremental updates are stale.
---

# /graph-rebuild — Rebuild Project Codebase Graph

You are the graph rebuilder. Your job is to wipe all project-derived nodes from the knowledge graph and rebuild them from the current codebase. The plugin seed graph (framework conventions, patterns, rules) is preserved.

## Instructions

---

### Step 0: VERIFY GIT REPOSITORY

Run `git rev-parse --is-inside-work-tree`. If not a git repository: **ERROR** — "Not a git repository." Abort.

---

### Step 1: CHECK AVAILABILITY

Run the health check script:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/neo4j-health.sh"
```

- If Neo4j is not healthy: **ERROR** — "Neo4j is not available. Run `/graph-init` to start the graph first." Abort.

---

### Step 2: CONFIRM WITH USER

Inform the user what will happen:

"This will delete all project nodes (`ProjectFile`, `ProjectClass`, `ProjectFunction`, `ProjectPackage`, `ProjectDependency`) and rebuild them from the current codebase. The plugin seed graph will not be affected."

Ask: **"Proceed with graph rebuild? (y/n)"**

- If the user says no: abort with "Rebuild cancelled."
- If the user says yes: continue.

---

### Step 3: DELETE PROJECT NODES

Delete all project-derived nodes and their relationships:

```bash
echo "MATCH (n) WHERE n:ProjectFile OR n:ProjectClass OR n:ProjectFunction OR n:ProjectPackage OR n:ProjectDependency DETACH DELETE n" | \
  docker exec -i pipeline-neo4j cypher-shell -u neo4j -p pipeline-local
```

- If the command exits non-zero: **ERROR** — display the error output. Do not proceed. The graph may be in a partial state — suggest running `/graph-init` to fully reinitialize.
- If successful: note how many nodes were deleted (cypher-shell reports `Deleted N nodes, deleted M relationships`).

Also clear the stale build marker so the next step always runs:

```bash
rm -f .pipeline/graph/.last-build-sha
```

---

### Step 4: REBUILD PROJECT GRAPH

Re-run the build script and pipe output to Neo4j:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/build-project-graph.sh" --project-root . | \
  docker exec -i pipeline-neo4j cypher-shell -u neo4j -p pipeline-local
```

- If the command exits non-zero: **ERROR** — display the error output and suggest checking that `build-project-graph.sh` is executable and that the project root is correct.
- If successful: write the current commit SHA to `.pipeline/graph/.last-build-sha`:

```bash
git rev-parse HEAD > .pipeline/graph/.last-build-sha
```

---

### Step 5: REPORT NEW NODE COUNTS

Query and display the updated node counts:

```bash
echo "MATCH (n) RETURN labels(n)[0] AS label, count(*) AS count ORDER BY count DESC" | \
  docker exec -i pipeline-neo4j cypher-shell -u neo4j -p pipeline-local --format plain
```

Present a summary:

```
Graph rebuilt successfully.

  Deleted:     142 project nodes, 350 relationships
  Build SHA:   <sha>

  Node counts after rebuild:
    ProjectFile        138
    ProjectClass        41
    ProjectFunction    228
    ProjectPackage      13
    ProjectDependency   27
    _SeedMarker          1    (seed preserved)

  Run /graph-status for enrichment coverage details.
  Run /graph-query to explore the graph.
```

If any step failed partway through, clearly indicate the graph may be in an inconsistent state and suggest running `/graph-init` to fully reinitialize.
