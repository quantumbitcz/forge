# SurrealDB Best Practices

## Overview
SurrealDB is a multi-model database supporting document, graph, relational, and time-series data in a single engine with built-in auth, real-time queries, and a Rust-based core. Use it for rapid prototyping, applications needing mixed data models, and projects wanting a single database for documents, graphs, and relational queries. Avoid it for production-critical workloads at scale (still maturing), when a proven single-model database (PostgreSQL, MongoDB, Neo4j) better fits your use case, or when ecosystem maturity matters.

## Architecture Patterns

**SurrealQL — multi-model queries:**
```sql
-- Document-style
CREATE user:alice SET name = "Alice", email = "alice@example.com", active = true;

-- Graph relationships
RELATE user:alice->follows->user:bob;
RELATE user:alice->authored->post:hello SET created_at = time::now();

-- Relational-style joins
SELECT name, ->follows->name AS following FROM user WHERE active = true;

-- Graph traversal
SELECT ->follows->follows->name AS friends_of_friends FROM user:alice;
```

**Record links and graph queries:**
```sql
-- Direct record link (typed reference)
CREATE order SET user = user:alice, items = [
  { product: product:widget, qty: 2, price: 9.99 }
];

-- Traverse links
SELECT user.name, items.product.name FROM order;
```

**Live queries (real-time subscriptions):**
```sql
LIVE SELECT * FROM order WHERE status = 'pending';
```

**Anti-pattern — using SurrealDB for workloads requiring battle-tested ACID guarantees at scale: SurrealDB is evolving rapidly. For financial transactions or regulatory-critical data, use PostgreSQL or CockroachDB until SurrealDB's transaction model matures.

## Configuration

```bash
# Start SurrealDB
surreal start --log trace --user root --pass root --bind 0.0.0.0:8000 file:data.db

# Docker
docker run --rm -p 8000:8000 surrealdb/surrealdb:latest start --user root --pass root file:/data/db.surreal
```

## Dos
- Use record IDs (`table:id`) for direct record access — they're fast and type-safe.
- Use `RELATE` for graph relationships — SurrealDB handles graph traversals natively.
- Use namespaces and databases for multi-tenancy isolation.
- Use `DEFINE FIELD` with type constraints for schema validation.
- Use `DEFINE INDEX` for frequently queried fields.
- Use `DEFINE SCOPE` and `DEFINE TOKEN` for built-in authentication.
- Start with embedded mode (`file:`) for development, switch to TiKV backend for production scale.

## Don'ts
- Don't use SurrealDB for mission-critical financial transactions without thorough testing — it's still maturing.
- Don't skip schema definitions — while flexible, untyped fields cause data quality issues.
- Don't use root credentials in production — create scoped users with minimal permissions.
- Don't rely on SurrealDB for large-scale analytics — use dedicated OLAP databases.
- Don't ignore backup strategies — use `surreal export` for regular backups.
- Don't assume feature parity with PostgreSQL or MongoDB — verify capabilities before committing.
- Don't use live queries without connection management — disconnected clients leave orphaned subscriptions.
