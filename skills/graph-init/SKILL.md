---
name: graph-init
description: Initialize Neo4j knowledge graph. Starts Docker container, imports plugin seed, builds project codebase graph. Requires /pipeline-init to have run first. Idempotent.
---

# /graph-init — Neo4j Knowledge Graph Initialization

You are the graph initializer. Your job is to start the Neo4j container, import the plugin seed data, and build the project codebase graph. Be idempotent — detect what is already done and skip those steps.

## Instructions

Work through these steps in order.

---

### Step 1: VERIFY PREREQUISITES

1. Check that `.claude/dev-pipeline.local.md` exists in the project root.
   - If it does not exist: **ERROR** — "Pipeline not initialized. Run `/pipeline-init` first." Abort.

2. Read `.claude/dev-pipeline.local.md` and check `graph.enabled`.
   - If `graph.enabled: false` or the `graph:` section is absent: inform the user — "Graph integration is disabled in `dev-pipeline.local.md`. Set `graph.enabled: true` to use this feature." Exit.

3. Check Docker availability: `docker info`
   - If the command fails: **WARN** — "Docker is not available. Cannot start Neo4j container."
   - Update `.pipeline/state.json` integrations: `"neo4j": {"available": false}`
   - Abort.

---

### Step 2: PREPARE COMPOSE FILE

Copy the Docker Compose template to the pipeline working directory:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/shared/graph/docker-compose.neo4j.yml" .pipeline/docker-compose.neo4j.yml
```

Substitute port variables from config (read `graph.neo4j_port` and `graph.neo4j_bolt_port` from `dev-pipeline.local.md`, defaulting to `7474` and `7687` respectively). Edit the copied file to replace placeholder values with the resolved ports.

---

### Step 3: START CONTAINER

Check if the container is already running:

```bash
docker ps --filter "name=pipeline-neo4j" --format "{{.Names}}"
```

- If `pipeline-neo4j` appears in output: **skip** this step — container is already running.
- If not running: start it:

```bash
docker compose -f .pipeline/docker-compose.neo4j.yml up -d
```

---

### Step 4: WAIT FOR HEALTH

Poll the health check script until Neo4j is ready, up to 60 seconds:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/neo4j-health.sh"
```

Run this in a loop (every 3 seconds) until it exits 0 or 60 seconds have elapsed.

- If Neo4j becomes healthy within 60s: continue.
- If it does not respond after 60s: **ERROR** — "Neo4j did not become healthy within 60 seconds. Check container logs: `docker logs pipeline-neo4j`" Abort.

---

### Step 5: IMPORT PLUGIN SEED

Check for the seed marker node to determine if the seed has already been imported:

```bash
echo "MATCH (n:_SeedMarker {id: 'dev-pipeline-seed-v2'}) RETURN count(n)" | \
  docker exec -i pipeline-neo4j cypher-shell -u neo4j -p pipeline-local --format plain
```

- If count > 0: **skip** — seed already imported.
- If count = 0: import the seed:

```bash
cat "${CLAUDE_PLUGIN_ROOT}/shared/graph/seed.cypher" | \
  docker exec -i pipeline-neo4j cypher-shell -u neo4j -p pipeline-local
```

---

### Step 6: BUILD PROJECT GRAPH

Check `.pipeline/graph/.last-build-sha` — if it exists and matches the current `git rev-parse HEAD`, the graph is already up to date for this commit; skip rebuild and note this to the user.

Otherwise, build the project graph:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/build-project-graph.sh" --project-root . | \
  docker exec -i pipeline-neo4j cypher-shell -u neo4j -p pipeline-local
```

After success, write the current commit SHA to `.pipeline/graph/.last-build-sha`.

Create `.pipeline/graph/` directory if it does not exist.

---

### Step 7: UPDATE STATE

Update `.pipeline/state.json` integrations block:

```json
"neo4j": {
  "available": true
}
```

If `.pipeline/state.json` does not exist or has no `integrations` key, create/add the key. Do not overwrite unrelated fields.

---

### Step 8: REPORT

Query and display node counts:

```bash
echo "MATCH (n) RETURN labels(n)[0] AS label, count(*) AS count ORDER BY count DESC" | \
  docker exec -i pipeline-neo4j cypher-shell -u neo4j -p pipeline-local --format plain
```

Present a summary:

```
Graph initialized successfully.

  Container:   pipeline-neo4j (running)
  Seed:        imported
  Build SHA:   <sha>

  Node counts:
    ProjectFile        142
    ProjectClass        38
    ProjectFunction    215
    ...

  Run /graph-query to explore the graph.
  Run /graph-status for health and coverage details.
```

Note any steps that were skipped (idempotency).
