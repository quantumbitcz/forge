---
name: graph-rebuild
description: Rebuild the project codebase graph from scratch. Keeps the plugin seed graph intact. Use when incremental updates are stale.
---

# /graph-rebuild — Rebuild Project Codebase Graph

You are the graph rebuilder. Your job is to wipe all project-derived nodes from the knowledge graph and rebuild them from the current codebase. The plugin seed graph (framework conventions, patterns, rules) is preserved.

## Container Name Resolution

Before starting, resolve the Neo4j container name: read `graph.neo4j_container_name` from `.claude/forge.local.md`. If not set, use default `forge-neo4j`. Use the resolved name in ALL `docker` commands below.

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

"This will delete all project nodes (`ProjectFile`, `ProjectClass`, `ProjectFunction`, `ProjectPackage`, `ProjectDependency`) and rebuild them from the current codebase. The plugin seed graph will not be affected. Bugfix enrichment data (bug_fix_count, last_bug_fix_date) is preserved by default."

Use `AskUserQuestion` to confirm:
- Header: "Graph Rebuild"
- Question: "This will delete all project graph nodes and rebuild them from the current codebase. The plugin seed graph is not affected. Bugfix enrichment is preserved unless --clear-enrichment is specified."
- Options: "Rebuild — delete project nodes and rebuild from codebase (preserves enrichment)" / "Cancel — keep current graph"

---

### Component-Scoped Rebuild

Accept optional `--component <name>` argument:
- Without `--component`: rebuild all components for current project
- With `--component api`: rebuild only the `api` component

Deletion is always scoped to current project — never touches other projects' nodes.

### Enrichment Preservation

By default, `ProjectFile` enrichment properties (`bug_fix_count`, `last_bug_fix_date`) are **preserved** across rebuilds. The deletion step saves enrichment data before deleting, and the rebuild step restores it.

Accept optional `--clear-enrichment` flag to wipe all enrichment data. Useful when enrichment is stale or after significant codebase restructuring.

---

### Step 3: DELETE PROJECT NODES

**Step 3a: Save enrichment data** (skip if `--clear-enrichment`):

```bash
echo "MATCH (n:ProjectFile) WHERE n.bug_fix_count > 0 RETURN n.path AS path, n.bug_fix_count AS count, n.last_bug_fix_date AS date" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain > /tmp/forge-enrichment-backup.csv
```

**Step 3b: Delete all project-derived nodes** and their relationships:

```bash
echo "MATCH (n) WHERE n:ProjectFile OR n:ProjectClass OR n:ProjectFunction OR n:ProjectPackage OR n:ProjectDependency DETACH DELETE n" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local
```

- If the command exits non-zero: **ERROR** — display the error output. Do not proceed. The graph may be in a partial state — suggest running `/graph-init` to fully reinitialize.
- If successful: note how many nodes were deleted (cypher-shell reports `Deleted N nodes, deleted M relationships`).

Also clear the stale build marker so the next step always runs:

```bash
rm -f .forge/graph/.last-build-sha
```

---

### Step 4: REBUILD PROJECT GRAPH

Re-run the build script and pipe output to Neo4j:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/build-project-graph.sh" --project-root . | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local
```

- If the command exits non-zero: **ERROR** — display the error output and suggest checking that `build-project-graph.sh` is executable and that the project root is correct.
- If successful: write the current commit SHA to `.forge/graph/.last-build-sha`:

```bash
git rev-parse HEAD > .forge/graph/.last-build-sha
```

### Step 4b: RESTORE ENRICHMENT (skip if `--clear-enrichment`)

If enrichment data was saved in Step 3a and the backup file is non-empty, restore it:

```bash
# Parse the CSV and apply enrichment via MERGE
while IFS=',' read -r path count date; do
  [ -z "$path" ] && continue
  echo "MATCH (n:ProjectFile {path: '$path'}) SET n.bug_fix_count = $count, n.last_bug_fix_date = '$date';"
done < /tmp/forge-enrichment-backup.csv | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local
```

- If restoration fails: log WARNING "Enrichment restoration failed — enrichment data lost. Bugfix telemetry will restart from zero." Continue — this is non-blocking.
- Clean up: `rm -f /tmp/forge-enrichment-backup.csv`

---

### Step 5: REPORT NEW NODE COUNTS

Query and display the updated node counts:

```bash
echo "MATCH (n) RETURN labels(n)[0] AS label, count(*) AS count ORDER BY count DESC" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain
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
