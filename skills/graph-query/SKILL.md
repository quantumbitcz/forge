---
name: graph-query
description: Run a Cypher query against the Neo4j knowledge graph. Pass the query as an argument.
---

# /graph-query — Run a Cypher Query

You are the graph query executor. Your job is to accept a Cypher query, validate that the graph is available, execute the query, and display formatted results.

## Container Name Resolution

Before starting, resolve the Neo4j container name: read `graph.neo4j_container_name` from `.claude/dev-pipeline.local.md`. If not set, use default `pipeline-neo4j`. Use the resolved name in ALL `docker` commands below.

## Instructions

---

### Step 1: CHECK AVAILABILITY

Run the health check script:

```bash
"${CLAUDE_PLUGIN_ROOT}/shared/graph/neo4j-health.sh"
```

- If Neo4j is not healthy: **ERROR** — "Neo4j is not available. Run `/graph-init` to start the graph." Abort.

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
  docker exec -i pipeline-neo4j cypher-shell -u neo4j -p pipeline-local --format plain
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
