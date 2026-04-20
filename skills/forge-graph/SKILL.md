---
name: forge-graph
description: "[writes for init/rebuild, read-only for status/query/debug] Manage the Neo4j knowledge graph. Subcommands: init, status, query <cypher>, rebuild, debug. Requires Docker. No default — an explicit subcommand is required."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent']
disable-model-invocation: false
---

# /forge-graph — Knowledge Graph Management

One skill, five subcommands. Each subcommand preserves the behavior of the corresponding Phase 1 skill verbatim.

## Subcommand dispatch

Follow `shared/skill-subcommand-pattern.md`. This skill uses **positional subcommands**, NOT flags.

**Dispatch rules:**

1. Read `$ARGUMENTS`.
2. Split: `SUB="$1"; shift; REST="$*"`.
3. If `$SUB` is empty OR matches `-*` (bare invocation or flags-only): print the usage block and exit 2 (`No subcommand provided. Valid: init | status | query | rebuild | debug.`).
4. If `$SUB == --help` OR `$SUB == help`: print usage and exit 0.
5. If `$SUB` is in `{init, status, query, rebuild, debug}`: dispatch to the matching `### Subcommand: <SUB>` section with `$REST` as its arguments.
6. Otherwise: print `Unknown subcommand '<SUB>'. Valid: init | status | query | rebuild | debug. Try /forge-graph --help.` and exit 2.

**No default subcommand.** This is intentional — `rebuild` is destructive, so a bare `/forge-graph` must not silently rebuild.

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: preview actions without writing (applicable to `init`, `rebuild`)
- **--json**: structured JSON output (applicable to `status`, `debug`)

Subcommand-specific flags are documented under each subcommand section.

## Exit codes

See `shared/skill-contract.md` §3.

## Shared prerequisites

Before any subcommand:

1. **Forge initialized:** `.claude/forge.local.md` exists. If not: "Pipeline not initialized. Run `/forge-init` first." STOP.
2. **Graph enabled:** `graph.enabled: true` in `forge.local.md`. If false/absent: "Graph integration is disabled. Set `graph.enabled: true` to use this feature." STOP.
3. **Docker available:** `docker info`. If fails: "Docker is not available. Cannot run graph operations." STOP.

## Container name resolution

Read `graph.neo4j_container_name` from `.claude/forge.local.md`. If not set, default: `forge-neo4j`. Use the resolved name in ALL `docker` commands below.

---

### Subcommand: init

You are the graph initializer. Your job is to start the Neo4j container, import the plugin seed data, and build the project codebase graph. Be idempotent — detect what is already done and skip those steps.

#### Step 1: VERIFY PREREQUISITES

1. Check that `.claude/forge.local.md` exists in the project root.
   - If it does not exist: **ERROR** — "Pipeline not initialized. Run `/forge-init` first." Abort.

2. Read `.claude/forge.local.md` and check `graph.enabled`.
   - If `graph.enabled: false` or the `graph:` section is absent: inform the user — "Graph integration is disabled in `forge.local.md`. Set `graph.enabled: true` to use this feature." Exit.

3. Check Docker availability: `docker info`
   - If the command fails: **WARN** — "Docker is not available. Cannot start Neo4j container."
   - Update `.forge/state.json` integrations: `"neo4j": {"available": false}`
   - Abort.

#### Step 2: PREPARE COMPOSE FILE

Copy the Docker Compose template to the pipeline working directory:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/shared/graph/docker-compose.neo4j.yml" .forge/docker-compose.neo4j.yml
```

Substitute port variables from config (read `graph.neo4j_port` and `graph.neo4j_bolt_port` from `forge.local.md`, defaulting to `7474` and `7687` respectively). Edit the copied file to replace placeholder values with the resolved ports.

#### Step 3: START CONTAINER

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

#### Step 4: WAIT FOR HEALTH

Poll the health check script until Neo4j is ready, up to 60 seconds:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/neo4j-health.sh"
```

Run this in a loop (every 3 seconds) until it exits 0 or 60 seconds have elapsed.

- If Neo4j becomes healthy within 60s: continue.
- If it does not respond after 60s: **ERROR** — "Neo4j did not become healthy within 60 seconds. Check container logs: `docker logs forge-neo4j`" Abort.

#### Step 5: IMPORT PLUGIN SEED

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

#### Step 6: BUILD PROJECT GRAPH

Check `.forge/graph/.last-build-sha` — if it exists and matches the current `git rev-parse HEAD`, the graph is already up to date for this commit; skip rebuild and note this to the user.

##### Project Identity

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

#### Step 7: UPDATE STATE

Update `.forge/state.json` integrations block:

```json
"neo4j": {
  "available": true
}
```

If `.forge/state.json` does not exist or has no `integrations` key, create/add the key. Do not overwrite unrelated fields.

#### Step 8: REPORT

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

  Run /forge-graph query to explore the graph.
  Run /forge-graph status for health and coverage details.
```

Note any steps that were skipped (idempotency).

Key behavior preserved:
- Idempotent: skips steps that are already done (container running, seed imported, build-SHA matches HEAD).
- Writes `.forge/graph/.last-build-sha` on success.
- Updates `.forge/state.json.integrations.neo4j.available = true`.
- Pulls `neo4j:5-community` if image not present locally.

### Subcommand: status

You are the graph status reporter. Your job is to display the current state of the Neo4j knowledge graph: container health, node and relationship counts, last build SHA, and enrichment coverage.

Read-only. Honors `--json` flag per skill-contract §2.

#### Additional prerequisites

- **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
- **Neo4j available:** Check Docker container running. If not: report "Neo4j not running. Run `/forge-graph init` first." and STOP.

#### Step 1: CONTAINER HEALTH

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

##### Per-Project Node Counts

Show node counts grouped by project:
```cypher
MATCH (n) WHERE n.project_id IS NOT NULL
RETURN n.project_id, labels(n)[0] AS label, count(n) AS count
ORDER BY n.project_id, label
```

#### Step 2: NODE COUNTS

If Neo4j is healthy, query node counts by label:

```bash
echo "MATCH (n) RETURN labels(n)[0] AS label, count(*) AS count ORDER BY count DESC" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain
```

Display all results in a table.

#### Step 3: LAST BUILD SHA

Read `.forge/graph/.last-build-sha` and display its contents.

- If the file does not exist: show "No build recorded yet."
- If the file exists: also compare to `git rev-parse HEAD` and indicate whether the graph is **up to date** or **stale** (HEAD has moved since last build).

#### Step 4: ENRICHMENT COVERAGE

Read `.forge/graph/.enriched-files` if it exists.

- Show total number of enriched files.
- Show percentage of project source files covered (compare to total files tracked by git: `git ls-files | wc -l`).
- If the file does not exist: show "No enrichment data recorded."

#### Step 5: RELATIONSHIP COUNTS

If Neo4j is healthy, query relationship counts:

```bash
echo "MATCH ()-[r]->() RETURN type(r) AS type, count(*) AS count ORDER BY count DESC" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain
```

Display all results in a table.

#### Step 6: REPORT

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

  Run /forge-graph init to rebuild if stale.
  Run /forge-graph query <cypher> to explore.
```

If Neo4j is unavailable, show what can be determined from local files (last build SHA, enriched files) and suggest running `/forge-graph init`.

### Subcommand: query

You are the graph query executor. Your job is to accept a Cypher query (everything after `query` on the command line), validate that the graph is available, execute the query, and display formatted results.

Takes the Cypher query as a positional argument. If no argument: prompts the user. Read-only.

#### Additional prerequisites

- **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
- **Neo4j available:** Check Docker container running. If not: report "Neo4j not running. Run `/forge-graph init` first." and STOP.

#### Step 1: CHECK AVAILABILITY

Run the health check script:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/neo4j-health.sh"
```

- If Neo4j is not healthy: **ERROR** — "Neo4j is not available. Run `/forge-graph init` to start the graph." Abort.

##### Default Parameters

Inject `project_id` automatically into all queries:
```bash
PROJECT_ID=$(derive_project_id "$PROJECT_ROOT")
```

User can override by specifying their own `:param project_id` in the query, or omit `project_id` for cross-project queries.

#### Step 2: GET QUERY

Accept the Cypher query from the skill argument (the text following `query` on the command line).

- If no argument is provided: prompt the user — "Enter your Cypher query:"
- Wait for the user to type the query before proceeding.

Store the query in `$QUERY`.

#### Step 3: EXECUTE QUERY

Run the query against Neo4j:

```bash
echo "$QUERY" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain
```

Capture both stdout and stderr.

- If the command exits 0: display the results (see Step 4).
- If it exits non-zero: display the error output and suggest checking query syntax. Do not retry automatically.

#### Step 4: FORMAT AND DISPLAY RESULTS

Present the raw output from cypher-shell. If the output is empty (no rows returned), show: "Query returned no results."

Also show the query that was executed, so the user can reference or modify it:

```
Query:
  MATCH (n:ProjectClass) RETURN n.name LIMIT 10

Results:
  n.name
  ------
  UserService
  OrderRepository
  PaymentGateway
  ...

  (3 rows)
```

If the output is large (more than 50 rows), truncate display to 50 rows and note: "Showing first 50 of N rows. Add a LIMIT clause to restrict results."

#### Step 5: FOLLOW-UP

After displaying results, offer useful next steps based on the query type:

- If the query was a `MATCH ... RETURN` with no LIMIT: suggest adding `LIMIT` for large graphs.
- If the query returned 0 results: suggest checking node labels with `MATCH (n) RETURN DISTINCT labels(n)`.
- Always remind the user they can run `/forge-graph status` to see all available labels and relationship types.

### Subcommand: rebuild

You are the graph rebuilder. Your job is to wipe all project-derived nodes from the knowledge graph and rebuild them from the current codebase. The plugin seed graph (framework conventions, patterns, rules) is preserved.

Honors `--component <name>`, `--clear-enrichment`, and `--dry-run` flags. Uses `AskUserQuestion` for the confirmation step. Destructive — deletes project-scoped nodes (preserves plugin seed).

#### Additional prerequisites

- **Git repository:** Run `git rev-parse --is-inside-work-tree`. If not: report "Not a git repository." and STOP.
- **Neo4j available:** Run the health check script. If not healthy: report "Neo4j is not available. Run `/forge-graph init` to start the graph first." and STOP.

#### Step 0: VERIFY GIT REPOSITORY

Run `git rev-parse --is-inside-work-tree`. If not a git repository: **ERROR** — "Not a git repository." Abort.

#### Step 1: CHECK AVAILABILITY

Run the health check script:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/neo4j-health.sh"
```

- If Neo4j is not healthy: **ERROR** — "Neo4j is not available. Run `/forge-graph init` to start the graph first." Abort.

#### Step 2: CONFIRM WITH USER

Inform the user what will happen:

"This will delete all project nodes (`ProjectFile`, `ProjectClass`, `ProjectFunction`, `ProjectPackage`, `ProjectDependency`) and rebuild them from the current codebase. The plugin seed graph will not be affected. Bugfix enrichment data (bug_fix_count, last_bug_fix_date) is preserved by default."

Use `AskUserQuestion` to confirm:
- Header: "Graph Rebuild"
- Question: "This will delete all project graph nodes and rebuild them from the current codebase. The plugin seed graph is not affected. Bugfix enrichment is preserved unless --clear-enrichment is specified."
- Options: "Rebuild — delete project nodes and rebuild from codebase (preserves enrichment)" / "Cancel — keep current graph"

##### Component-Scoped Rebuild

Accept optional `--component <name>` argument:
- Without `--component`: rebuild all components for current project
- With `--component api`: rebuild only the `api` component

Deletion is always scoped to current project — never touches other projects' nodes.

##### Enrichment Preservation

By default, `ProjectFile` enrichment properties (`bug_fix_count`, `last_bug_fix_date`) are **preserved** across rebuilds. The deletion step saves enrichment data before deleting, and the rebuild step restores it.

Accept optional `--clear-enrichment` flag to wipe all enrichment data. Useful when enrichment is stale or after significant codebase restructuring.

#### Step 3: RESOLVE PROJECT IDENTITY

Derive the `project_id` for scoping all queries:

```bash
PROJECT_ID=$(git remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||; s|\.git$||')
# Fallback for repos without a remote:
[ -z "$PROJECT_ID" ] && PROJECT_ID=$(basename "$(git rev-parse --show-toplevel)")
```

All Cypher queries in this step MUST include `n.project_id = '$PROJECT_ID'` to avoid affecting other projects sharing the same Neo4j instance.

#### Step 3a: SAVE ENRICHMENT DATA (skip if `--clear-enrichment`)

```bash
echo "MATCH (n:ProjectFile {project_id: '$PROJECT_ID'}) WHERE n.bug_fix_count > 0 RETURN n.path AS path, n.bug_fix_count AS count, n.last_bug_fix_date AS date" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format csv > /tmp/forge-enrichment-backup.csv
```

#### Step 3b: DELETE PROJECT NODES

Delete project-derived nodes **scoped to current project only**:

```bash
echo "MATCH (n) WHERE (n:ProjectFile OR n:ProjectClass OR n:ProjectFunction OR n:ProjectPackage OR n:ProjectDependency) AND n.project_id = '$PROJECT_ID' DETACH DELETE n" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local
```

- If the command exits non-zero: **ERROR** — display the error output. Do not proceed. The graph may be in a partial state — suggest running `/forge-graph init` to fully reinitialize.
- If successful: note how many nodes were deleted (cypher-shell reports `Deleted N nodes, deleted M relationships`).

Also clear the stale build marker so the next step always runs:

```bash
rm -f .forge/graph/.last-build-sha
```

#### Step 4: REBUILD PROJECT GRAPH

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

#### Step 4b: RESTORE ENRICHMENT (skip if `--clear-enrichment`)

If enrichment data was saved in Step 3a and the backup file is non-empty, restore it:

```bash
# Parse the CSV and apply enrichment via MERGE
while IFS=',' read -r path count date; do
  [ -z "$path" ] && continue
  # Escape single quotes in path to prevent Cypher injection
  safe_path=$(printf '%s' "$path" | sed "s/'/''/g")
  echo "MATCH (n:ProjectFile {project_id: '$PROJECT_ID', path: '$safe_path'}) SET n.bug_fix_count = $count, n.last_bug_fix_date = '$date';"
done < /tmp/forge-enrichment-backup.csv | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local
```

- If restoration fails: log WARNING "Enrichment restoration failed — enrichment data lost. Bugfix telemetry will restart from zero." Continue — this is non-blocking.
- Clean up: `rm -f /tmp/forge-enrichment-backup.csv`

#### Step 5: REPORT NEW NODE COUNTS

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

  Run /forge-graph status for enrichment coverage details.
  Run /forge-graph query to explore the graph.
```

If any step failed partway through, clearly indicate the graph may be in an inconsistent state and suggest running `/forge-graph init` to fully reinitialize.

### Subcommand: debug

Targeted diagnostic skill for the Neo4j knowledge graph. Provides structured diagnostic recipes without requiring raw Cypher knowledge.

Read-only. Enforces `LIMIT 50` on every query. All queries scoped to `project_id`.

#### Additional prerequisites

- **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
- **Neo4j container running:** Run `shared/graph/neo4j-health.sh`. If unhealthy: report "Neo4j is not available. Run `/forge-graph init` first." and STOP.
- **Graph initialized:** Verify graph has nodes (check via node count query). If empty: report "Graph is empty. Run `/forge-graph init` to build the project graph." and STOP.

#### Diagnostic Recipes

##### 1. Orphaned Nodes

Nodes with no relationships (potential data quality issue):

```cypher
MATCH (n {project_id: $project_id})
WHERE NOT (n)--()
RETURN labels(n) AS type, count(n) AS count
LIMIT 50
```

##### 2. Stale Nodes

Nodes not updated since the current HEAD:

```cypher
MATCH (n {project_id: $project_id})
WHERE n.last_updated_sha <> $current_sha
RETURN labels(n)[0] AS type, n.name AS name, n.last_updated_sha AS stale_sha
LIMIT 50
```

##### 3. Missing Enrichments

Expected enrichment properties absent on node types:

```cypher
MATCH (n:Function {project_id: $project_id})
WHERE n.complexity IS NULL OR n.test_coverage IS NULL
RETURN n.name AS function, n.file_path AS file
LIMIT 50
```

##### 4. Relationship Integrity

Check for expected relationship types:

```cypher
MATCH (n {project_id: $project_id})
WHERE NOT (n)-[:DEFINED_IN]->()
RETURN labels(n)[0] AS type, n.name AS name
LIMIT 50
```

##### 5. Node Count Summary

Quick health overview by label:

```cypher
MATCH (n {project_id: $project_id})
RETURN labels(n)[0] AS label, count(n) AS count
ORDER BY count DESC
LIMIT 50
```

#### Instructions

1. Run Neo4j health check via `shared/graph/neo4j-health.sh`
2. If unhealthy: report status and suggest `/forge-graph init` or Docker troubleshooting
3. If healthy: derive `project_id` from git remote origin URL
4. Run diagnostic recipes 1-5, report findings in table format
5. If user provides a specific concern, run targeted Cypher (read-only, enforce LIMIT)
6. Suggest remediation: `/forge-graph rebuild` for widespread staleness, manual fixes for isolated issues

#### Safety

- All queries are READ-ONLY (no CREATE, MERGE, DELETE, SET)
- All queries enforce LIMIT (max 50 rows default, configurable)
- Never modify graph state -- diagnostic only

## Error Handling

Inherits the error-handling tables from each of the five Phase-1 source skills. Consolidated matrix:

| Condition | Action |
|---|---|
| Shared prerequisites fail | Report specific error and STOP |
| Docker image pull fails (init) | "Failed to pull Neo4j image. Check internet + Docker Hub access." STOP |
| Neo4j health timeout (60s) | "Neo4j did not become healthy within 60 seconds. Check `docker logs forge-neo4j`." STOP |
| Container not running (status/query/rebuild/debug) | "Neo4j not running. Run `/forge-graph init` first." STOP (or show local file data for status) |
| Seed import fails (init) | "Container is running but seed is missing. Retry `/forge-graph init`." |
| Query returns no results (query) | "Query returned no results. Check labels with `MATCH (n) RETURN DISTINCT labels(n)`." |
| User cancels rebuild | "Rebuild cancelled. Graph unchanged." STOP |
| Deletion fails mid-rebuild | "Graph may be in partial state. Run `/forge-graph init` to fully reinitialize." STOP |
| Enrichment restore fails | WARNING "Bugfix telemetry will restart from zero." Continue |

## See Also

- `/forge-ask` — Natural-language queries over the graph
- `/forge-init` — Full project setup (may invoke `/forge-graph init` as a step)
