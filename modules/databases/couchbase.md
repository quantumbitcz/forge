# Couchbase Best Practices

## Overview
Couchbase is a distributed NoSQL document database with integrated full-text search, analytics, and eventing. Use it for high-availability applications needing sub-millisecond key-value lookups, SQL++ (N1QL) queries on JSON documents, and cross-datacenter replication. Couchbase excels at session stores, user profiles, and mobile sync (via Couchbase Lite/Sync Gateway). Avoid it for purely relational workloads with complex joins, analytics-heavy workloads (use ClickHouse), or when simpler document stores (MongoDB) suffice.

## Architecture Patterns

**Key-value operations (fastest path):**
```javascript
const cluster = await couchbase.connect("couchbase://cb.internal", { username: "app", password: "..." });
const bucket = cluster.bucket("myapp");
const collection = bucket.defaultCollection();

// Sub-millisecond KV operations
await collection.upsert("user::123", { name: "Alice", email: "alice@example.com" });
const result = await collection.get("user::123");
```

**SQL++ (N1QL) queries:**
```sql
SELECT u.name, u.email, COUNT(o.id) AS order_count
FROM myapp u
JOIN myapp o ON META(o).id LIKE "order::%"
  AND o.userId = META(u).id
WHERE u.type = "user" AND u.active = true
GROUP BY u.name, u.email
ORDER BY order_count DESC
LIMIT 20;
```

**Full-text search (integrated):**
```javascript
const result = await cluster.searchQuery("product-search",
  couchbase.SearchQuery.match("wireless headphones"),
  { fields: ["name", "description"], limit: 20 });
```

**Anti-pattern — storing all document types in the default collection without type discrimination:** Use scopes and collections (Couchbase 7.0+) to separate document types. Without them, use a `type` field and create appropriate indexes.

## Configuration

```yaml
# Docker Compose
couchbase:
  image: couchbase:7.2
  ports: ["8091-8096:8091-8096", "11210:11210"]
  environment:
    COUCHBASE_ADMINISTRATOR_USERNAME: admin
    COUCHBASE_ADMINISTRATOR_PASSWORD: password
```

## Performance

**Use EXPLAIN for N1QL query analysis:**
```sql
EXPLAIN SELECT * FROM myapp WHERE type = "user" AND email = "alice@example.com";
```
Look for: `PrimaryScan` (missing index), `IntersectScan` (consider compound index).

**Index design — covered indexes:**
```sql
CREATE INDEX idx_users_email ON myapp(email) WHERE type = "user";
CREATE INDEX idx_orders_user ON myapp(userId, total) WHERE type = "order";
```

**Memory-first architecture:** Couchbase serves KV ops from the managed cache (bucket RAM quota). Size RAM to hold the working set. Cache misses hit disk and add latency.

**Use `subdoc` operations for partial reads/writes:**
```javascript
await collection.mutateIn("user::123", [couchbase.MutateInSpec.upsert("lastLogin", new Date().toISOString())]);
const result = await collection.lookupIn("user::123", [couchbase.LookupInSpec.get("email")]);
```

## Security

**RBAC (role-based access control):**
```sql
CREATE USER app_user IDENTIFIED BY 'strong-password';
GRANT data_reader, data_writer ON myapp TO app_user;
```

**TLS encryption:** Enable TLS for client connections and inter-node communication. Use `couchbases://` (TLS) instead of `couchbase://`.

**Parameterized N1QL queries:** Always use `$param` placeholders — never concatenate user input into N1QL strings.

**Audit logging:** Enable audit events for data access and admin operations in the Security settings.

## Testing

Use **Testcontainers** for integration tests:
```javascript
const container = new CouchbaseContainer("couchbase:7.2").withBucket({ name: "test" });
await container.start();
const cluster = await couchbase.connect(container.getConnectionString(), { username: "Administrator", password: "password" });
```

Test KV operations, N1QL queries, and full-text search separately. Verify index effectiveness with `EXPLAIN`.

## Dos
- Use KV operations for single-document access — they're 10x faster than N1QL queries.
- Use scopes and collections to organize documents by type — replaces the `type` field pattern.
- Create covered indexes for frequent queries — include all queried fields in the index.
- Use cross-datacenter replication (XDCR) for geo-distributed high availability.
- Use `durabilityLevel: "majority"` for critical writes to ensure data survives node failures.
- Monitor with Couchbase's built-in web console and Prometheus exporter.
- Use `SELECT META(doc).id` instead of storing IDs as document fields.

## Don'ts
- Don't use N1QL for single-document lookups — KV operations are faster and cheaper.
- Don't skip index creation — unindexed N1QL queries trigger full collection scans.
- Don't use the default bucket without scopes/collections in new projects — they're the modern way.
- Don't set bucket RAM quotas too low — Couchbase caches documents in memory for KV performance.
- Don't ignore rebalance operations after adding/removing nodes — data distribution becomes uneven.
- Don't use Couchbase for pure analytics — its analytics service handles OLAP, but ClickHouse is better.
- Don't store large binary objects as document values — use references to external object storage.
