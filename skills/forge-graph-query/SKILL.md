---
name: forge-graph-query
description: "Run a Cypher query against the Neo4j knowledge graph. Use when you need to find bug hotspots, trace cross-feature dependencies, check test coverage gaps, or explore module relationships. Pass the query as an argument."
---

# /forge-graph-query — Run a Cypher Query

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. **Neo4j available:** Check Docker container running. If not: report "Neo4j not running. Run /graph-init first." and STOP.

You are the graph query executor. Your job is to accept a Cypher query, validate that the graph is available, execute the query, and display formatted results.

## Container Name Resolution

Before starting, resolve the Neo4j container name: read `graph.neo4j_container_name` from `.claude/forge.local.md`. If not set, use default `forge-neo4j`. Use the resolved name in ALL `docker` commands below.

## Instructions

---

### Step 1: CHECK AVAILABILITY

Run the health check script:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/neo4j-health.sh"
```

- If Neo4j is not healthy: **ERROR** — "Neo4j is not available. Run `/graph-init` to start the graph." Abort.

---

### Default Parameters

Inject `project_id` automatically into all queries:
```bash
PROJECT_ID=$(derive_project_id "$PROJECT_ROOT")
```

User can override by specifying their own `:param project_id` in the query, or omit `project_id` for cross-project queries.

---

### Step 2: GET QUERY

Accept the Cypher query from the skill argument (the text following `/graph-query` on the command line).

- If no argument is provided: prompt the user — "Enter your Cypher query:"
- Wait for the user to type the query before proceeding.

Store the query in `$QUERY`.

---

### Step 3: EXECUTE QUERY

Run the query against Neo4j:

```bash
echo "$QUERY" | \
  docker exec -i forge-neo4j cypher-shell -u neo4j -p forge-local --format plain
```

Capture both stdout and stderr.

- If the command exits 0: display the results (see Step 4).
- If it exits non-zero: display the error output and suggest checking query syntax. Do not retry automatically.

---

### Step 4: FORMAT AND DISPLAY RESULTS

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

---

### Step 5: FOLLOW-UP

After displaying results, offer useful next steps based on the query type:

- If the query was a `MATCH ... RETURN` with no LIMIT: suggest adding `LIMIT` for large graphs.
- If the query returned 0 results: suggest checking node labels with `MATCH (n) RETURN DISTINCT labels(n)`.
- Always remind the user they can run `/graph-status` to see all available labels and relationship types.

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| Neo4j not healthy | Report "Neo4j is not available. Run `/graph-init` to start the graph." and STOP |
| No query provided | Prompt the user: "Enter your Cypher query:" |
| Invalid Cypher syntax | Display the error output from cypher-shell and suggest checking query syntax |
| Query returns no results | Report "Query returned no results." Suggest checking node labels with `MATCH (n) RETURN DISTINCT labels(n)` |
| Query returns too many rows (>50) | Truncate to 50 rows with note. Suggest adding LIMIT clause |
| Docker connection fails | Report "Cannot connect to Neo4j container. Check if Docker is running." and STOP |

## See Also

- `/graph-status` -- See available node labels and relationship types before querying
- `/graph-debug` -- Structured diagnostic recipes without needing raw Cypher knowledge
- `/graph-rebuild` -- Rebuild the graph if queries return stale or missing data
- `/graph-init` -- Initialize the graph if it is not running
- `/forge-ask` -- Natural language queries about the codebase (uses graph as one of its data sources)
