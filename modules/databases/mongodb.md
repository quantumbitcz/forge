# MongoDB Best Practices

## Overview
MongoDB is a document-oriented database suited for flexible schemas, hierarchical data, and rapid iteration where the schema evolves frequently. Use it for content management, event stores, product catalogs, and user-generated data with variable structure. Avoid MongoDB when your data is highly relational (many-to-many joins), when you need strong ACID guarantees across multiple collections, or when analytics-heavy workloads dominate.

## Architecture Patterns

**Embed for "owned" data, reference for "shared" data:**
```javascript
// EMBED: order items are owned by the order — always queried together
{
  _id: ObjectId("..."),
  userId: ObjectId("..."),   // REFERENCE: user exists independently
  items: [
    { sku: "WIDGET-1", qty: 2, price: 9.99 },
    { sku: "GADGET-7", qty: 1, price: 49.99 }
  ]
}
```
Rule of thumb: embed when the sub-document is always loaded with the parent and is bounded in size (< 16 MB document limit). Reference when the sub-document is large, unbounded in count, or accessed independently.

**Compound index aligned to query shape:**
```javascript
// Query: find active orders for a user, newest first
db.orders.createIndex({ userId: 1, status: 1, createdAt: -1 });
// ESR rule: Equality fields first, Sort fields second, Range fields last
```

**TTL index for auto-expiring documents:**
```javascript
db.sessions.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
// Document expires when Date.now() >= expiresAt
```

**Aggregation pipeline over application-side joins:**
```javascript
db.orders.aggregate([
  { $match: { status: "pending" } },
  { $lookup: { from: "users", localField: "userId", foreignField: "_id", as: "user" } },
  { $unwind: "$user" },
  { $project: { total: 1, "user.email": 1 } }
]);
```

**Anti-pattern — unbounded array growth:** Pushing to an array field indefinitely (e.g., all event log entries) causes documents to grow past 16 MB and triggers expensive document moves. Use a separate collection with a reference or a TTL collection.

## Configuration

**Connection string (production):**
```
mongodb+srv://app:pass@cluster.mongodb.net/mydb?
  retryWrites=true&w=majority&readPreference=primaryPreferred&
  maxPoolSize=50&connectTimeoutMS=5000&serverSelectionTimeoutMS=5000
```

**Write concern and read concern:**
```javascript
// OLTP: majority write concern ensures durability on replica set failover
db.runCommand({ writeConcern: { w: "majority", j: true } });
// Analytics reads can tolerate slightly stale data
db.collection.find(query).readPreference("secondaryPreferred");
```

**Replica set (always in production — never standalone):**
```yaml
# docker-compose snippet
command: mongod --replSet rs0 --bind_ip_all
# Initialize replica set
rs.initiate({ _id: "rs0", members: [{ _id: 0, host: "mongo1:27017" }] })
```

## Performance

**Use `explain("executionStats")` before shipping queries:**
```javascript
db.orders.find({ userId: ObjectId("...") }).explain("executionStats");
// Check: totalDocsExamined vs nReturned — ratio should be close to 1:1
```

**Projection to reduce document transfer:**
```javascript
// Fetch only needed fields — avoids transferring large embedded arrays
db.products.find({ category: "electronics" }, { name: 1, price: 1, _id: 0 });
```

**Avoid `$where` and `$regex` without anchors:** `$where` executes JavaScript per document (full scan). Unanchored regex (`/pattern/`) cannot use indexes; anchored regex (`/^pattern/`) can use a B-tree index prefix.

**Change streams for event-driven patterns (prefer over polling):**
```javascript
const stream = db.orders.watch([{ $match: { "operationType": "insert" } }]);
stream.on("change", (event) => processNewOrder(event.fullDocument));
```

**Index intersection is rare — prefer one compound index over multiple single-field indexes** for multi-field queries. MongoDB's query planner picks one index per query stage; it does not benefit from multiple indexes the way PostgreSQL does.

## Security

**Authentication — always enable (disabled by default in older versions):**
```javascript
db.createUser({
  user: "app",
  pwd: passwordPrompt(),
  roles: [{ role: "readWrite", db: "mydb" }]
});
```

**Never expose MongoDB port (27017) to the internet.** Use VPC/private network + application-layer auth. Enforce TLS:
```
mongod --tlsMode requireTLS --tlsCertificateKeyFile /etc/ssl/mongodb.pem
```

**Parameterized queries via driver (prevents NoSQL injection):**
```python
# SAFE: driver serializes to BSON
users.find_one({"email": email})
# UNSAFE: operator injection possible if email = {"$gt": ""}
users.find_one({"email": request.json["email"]})
```
Always validate/sanitize input before using it as a query filter.

**Field-level encryption** for PII (MongoDB CSFLE or application-level AES-256 before storing).

## Testing

Use **Testcontainers** for integration tests:
```java
@Container
static MongoDBContainer mongo = new MongoDBContainer("mongo:7.0");

@BeforeEach
void setUp() {
    MongoClient client = MongoClients.create(mongo.getConnectionString());
    database = client.getDatabase("testdb");
}
```

For unit tests of repository logic, use the **embedded MongoDB** (`de.flapdoodle.embed.mongo`) library or an in-memory mock. Prefer Testcontainers for behavioral fidelity (aggregation pipelines, indexes, TTL). Always test with `w: majority` write concern in tests that verify durability semantics.

## Dos
- Design schemas query-first: start from the queries your application will run, then design documents to serve those queries efficiently.
- Use compound indexes following the ESR rule (Equality → Sort → Range).
- Always run a replica set in production — MongoDB Atlas and most managed providers do this by default.
- Use `ObjectId` for `_id` fields; they encode creation time and are globally unique without coordination.
- Use the aggregation pipeline for server-side data transformation instead of fetching and processing in application code.
- Use TTL indexes for session tokens, cache documents, and temporary data instead of a background cleanup job.
- Enable `retryWrites=true` in the connection string to handle transient primary failover transparently.

## Don'ts
- Don't embed unbounded arrays in documents — they grow past 16 MB and cause performance degradation from document moves.
- Don't run MongoDB without authentication in any environment reachable from a network (default `--noauth` has caused mass data breaches).
- Don't use `$where` for filtering — it runs JavaScript per document, bypasses indexes, and is a security risk.
- Don't create indexes on every field speculatively — each write-path index slows inserts and consumes RAM in the WiredTiger cache.
- Don't skip write concern (`w: 0`) for data you care about — fire-and-forget acknowledges before the write reaches the journal.
- Don't assume multi-document atomicity without explicit transactions (MongoDB 4.0+) — multi-collection updates without `session.withTransaction()` can leave partial state on failure.
- Don't use `findAndModify` or `$push` for high-contention counter fields — use `$inc` with appropriate write concern, or move hot counters to Redis.
