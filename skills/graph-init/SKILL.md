---
name: graph-init
description: "Initialize Neo4j knowledge graph -- starts Docker container, imports plugin seed, builds project codebase graph. Use when setting up the knowledge graph for the first time, after Docker was restarted, or when /graph-status shows the graph is unavailable. Idempotent."
---

# /graph-init — Neo4j Knowledge Graph Initialization

You are the graph initializer. Your job is to start the Neo4j container, import the plugin seed data, and build the project codebase graph. Be idempotent — detect what is already done and skip those steps.

## Prerequisites

Before any action, verify:

1. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Pipeline not initialized. Run `/forge-init` first." and STOP.
2. **Graph enabled:** Read `graph.enabled` from `.claude/forge.local.md`. If `false` or absent: report "Graph integration is disabled in forge.local.md. Set `graph.enabled: true` to use this feature." and STOP.
3. **Docker available:** Run `docker info`. If fails: report "Docker is not available. Cannot start Neo4j container." and STOP.

## Container Name Resolution

Before starting, resolve the Neo4j container name:
1. Read `graph.neo4j_container_name` from `.claude/forge.local.md`
2. If not set, use default: `forge-neo4j`

Store the resolved name and use it in ALL `docker` commands below (replacing `forge-neo4j` in the examples).

## Instructions

Work through these steps in order.

---

### Step 1: VERIFY PREREQUISITES

1. Check that `.claude/forge.local.md` exists in the project root.
   - If it does not exist: **ERROR** — "Pipeline not initialized. Run `/forge-init` first." Abort.

2. Read `.claude/forge.local.md` and check `graph.enabled`.
   - If `graph.enabled: false` or the `graph:` section is absent: inform the user — "Graph integration is disabled in `forge.local.md`. Set `graph.enabled: true` to use this feature." Exit.

3. Check Docker availability: `docker info`
   - If the command fails: **WARN** — "Docker is not available. Cannot start Neo4j container."
   - Update `.forge/state.json` integrations: `"neo4j": {"available": false}`
   - Abort.

---

### Step 2: PREPARE COMPOSE FILE

Copy the Docker Compose template to the pipeline working directory:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/shared/graph/docker-compose.neo4j.yml" .forge/docker-compose.neo4j.yml
```

Substitute port variables from config (read `graph.neo4j_port` and `graph.neo4j_bolt_port` from `forge.local.md`, defaulting to `7474` and `7687` respectively). Edit the copied file to replace placeholder values with the resolved ports.

---

### Step 3: START CONTAINER

Check if the container is already running:

```bash
docker ps --filter "name=forge-neo4j" --format "{{.Names}}"
```

- If `forge-neo4j` appears in output: **skip** this step — container is already running.
- If not running: first check if the Neo4j image exists locally:

```bash
docker image inspect neo4j:5-community >/dev/null 2>&1
```

- If image NOT present: pull it explicitly first. This may take a moment on first run:

```bash
docker pull neo4j:5-community
```

- Then start the container:

```bash
docker compose -f .forge/docker-compose.neo4j.yml up -d
```

**Important:** The image tag `neo4j:5-community` uses a major-version floating tag, which always resolves to the latest 5.x release. This is intentional — Neo4j 5.x is backward-compatible within the major version. Do NOT pin to a specific patch version as it would require manual updates.

---

### Step 4: WAIT FOR HEALTH

Poll the health check script until Neo4j is ready, up to 60 seconds:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/neo4j-health.sh"
```

Run this in a loop (every 3 seconds) until it exits 0 or 60 seconds have elapsed.

- If Neo4j becomes healthy within 60s: continue.
- If it does not respond after 60s: **ERROR** — "Neo4j did not become healthy within 60 seconds. Check container logs: `docker logs forge-neo4j`" Abort.

---

### Step 5: IMPORT PLUGIN SEED

Check for the seed marker node to determine if the seed has already been imported:

```bash
echo "MATCH (n:_SeedMarker {id: 'forge-seed-v2'}) RETURN count(n)" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain
```

- If count > 0: **skip** — seed already imported.
- If count = 0: import the seed:

```bash
cat "${CLAUDE_PLUGIN_ROOT}/shared/graph/seed.cypher" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local
```

---

### Step 6: BUILD PROJECT GRAPH

Check `.forge/graph/.last-build-sha` — if it exists and matches the current `git rev-parse HEAD`, the graph is already up to date for this commit; skip rebuild and note this to the user.

### Project Identity

After container startup, derive project_id:
```bash
PROJECT_ID=$(derive_project_id "$PROJECT_ROOT")
```

Pass to build-project-graph.sh:
```bash
./shared/graph/build-project-graph.sh --project-root "$PROJECT_ROOT" --project-id "$PROJECT_ID"
```

For monorepo with components, iterate each component:
```bash
for component in $(read_components "$PROJECT_ROOT"); do
  ./shared/graph/build-project-graph.sh --project-root "$PROJECT_ROOT" --project-id "$PROJECT_ID" --component "$component"
done
```

Otherwise, build the project graph:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/build-project-graph.sh" --project-root . | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local
```

After success, write the current commit SHA to `.forge/graph/.last-build-sha`.

Create `.forge/graph/` directory if it does not exist.

---

### Step 7: UPDATE STATE

Update `.forge/state.json` integrations block:

```json
"neo4j": {
  "available": true
}
```

If `.forge/state.json` does not exist or has no `integrations` key, create/add the key. Do not overwrite unrelated fields.

---

### Step 8: REPORT

Query and display node counts:

```bash
echo "MATCH (n) RETURN labels(n)[0] AS label, count(*) AS count ORDER BY count DESC" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain
```

Present a summary:

```
Graph initialized successfully.

  Container:   forge-neo4j (running)
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

## Error Handling

| Condition | Action |
|-----------|--------|
| forge.local.md missing | Report "Pipeline not initialized. Run `/forge-init` first." and STOP |
| graph.enabled is false | Report "Graph integration is disabled in forge.local.md. Set `graph.enabled: true` to use this feature." and STOP |
| Docker not available | Report "Docker is not available. Cannot start Neo4j container." Update state integrations and STOP |
| Docker image pull fails | Report "Failed to pull Neo4j image. Check internet connection and Docker Hub access." and STOP |
| Container start fails | Report error output. Suggest checking port conflicts (`docker ps`) and disk space |
| Neo4j health timeout (60s) | Report "Neo4j did not become healthy within 60 seconds. Check container logs: `docker logs forge-neo4j`." and STOP |
| Seed import fails | Report error. Container is running but seed is missing. Suggest retrying `/graph-init` |
| Build script fails | Report error. Suggest checking that `build-project-graph.sh` is executable |
| State corruption | Graph init creates/updates state.json integrations block independently |

## See Also

- `/graph-status` -- Check graph health and node counts after initialization
- `/graph-query` -- Run Cypher queries against the initialized graph
- `/graph-rebuild` -- Rebuild project graph from scratch (preserves seed)
- `/graph-debug` -- Diagnose graph issues if initialization produced unexpected results
- `/forge-init` -- Full project setup which includes graph initialization as an optional step
