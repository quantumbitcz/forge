# Apache Cassandra Best Practices

## Overview
Cassandra is a distributed, wide-column database designed for high write throughput, linear horizontal scalability, and multi-datacenter replication with no single point of failure. Use it for time-series data, IoT telemetry, activity feeds, and workloads requiring billions of writes per day across multiple regions. Avoid Cassandra when you need ad-hoc queries, aggregations, or joins — its query model is strictly constrained by partition key design, and modeling mistakes are expensive to fix after data is loaded.

## Architecture Patterns

**Query-first data modeling — design tables around queries, not entities:**
```sql
-- Query: "Get last 100 events for device X"
CREATE TABLE device_events (
    device_id   UUID,
    occurred_at TIMESTAMP,
    event_type  TEXT,
    payload     TEXT,
    PRIMARY KEY (device_id, occurred_at)
) WITH CLUSTERING ORDER BY (occurred_at DESC)
  AND default_time_to_live = 2592000;  -- 30 days TTL

-- Separate table for a different query: "Get all events of type Y today"
CREATE TABLE events_by_type (
    event_type  TEXT,
    bucket_date DATE,
    occurred_at TIMESTAMP,
    device_id   UUID,
    PRIMARY KEY ((event_type, bucket_date), occurred_at)
) WITH CLUSTERING ORDER BY (occurred_at DESC);
```
One query pattern = one table. Denormalization is intentional and expected.

**Partition key design — control partition size:**
```sql
-- BAD: single partition key for all events of a type (unbounded partition)
PRIMARY KEY (event_type, occurred_at)

-- GOOD: time-bucket in the partition key limits partition size
PRIMARY KEY ((event_type, bucket_date), occurred_at)
-- Partition grows by ~1 day of data, not indefinitely
```
Target partition size < 100 MB. A single partition is served by one replica set — huge partitions cause hotspots and GC pressure.

**Lightweight transactions (LWT) sparingly:**
```sql
-- Compare-and-swap (Paxos-based — 4-10x slower than normal writes)
INSERT INTO user_emails (email, user_id)
VALUES ('alice@example.com', uuid())
IF NOT EXISTS;
```
Use LWT only for uniqueness enforcement or idempotent initialization. Never in hot write paths.

**Secondary indexes — use materialized views or separate tables instead:**
```sql
-- Cassandra secondary indexes scan all nodes — avoid in production
-- Instead, maintain a separate lookup table
CREATE TABLE users_by_email (
    email   TEXT PRIMARY KEY,
    user_id UUID
);
```

**Anti-pattern — wide row unbounded growth:** Storing all events for a user in a single partition without a time bucket causes the partition to grow indefinitely, eventually degrading reads, compaction, and repair.

## Configuration

**cassandra.yaml (production tuning):**
```yaml
# Replication factor (per keyspace, set at creation)
# RF=3 is the minimum for production; RF=5 for mission-critical

# Compaction — choose strategy per access pattern
# STCS: write-heavy append-only (default)
# LCS:  read-heavy, space-efficient, higher write amplification
# TWCS: time-series with TTL (best for time-bucketed data)
compaction:
  class: TimeWindowCompactionStrategy
  compaction_window_unit: HOURS
  compaction_window_size: 1

# Memory
memtable_heap_space_in_mb: 2048
file_cache_size_in_mb: 512

# Hints
hinted_handoff_enabled: true
max_hints_delivery_threads: 2
```

**Keyspace with multi-datacenter replication:**
```sql
CREATE KEYSPACE myapp WITH replication = {
    'class': 'NetworkTopologyStrategy',
    'us-east-1': 3,
    'eu-west-1': 3
};
```

**Driver configuration (Java — DataStax driver):**
```yaml
datastax-java-driver:
  basic.contact-points: ["cassandra1:9042", "cassandra2:9042"]
  basic.load-balancing-policy.local-datacenter: us-east-1
  advanced.reconnection-policy:
    class: ExponentialReconnectionPolicy
    base-delay: 1 second
    max-delay: 60 seconds
  advanced.retry-policy.class: DefaultRetryPolicy
```

## Performance

**Consistency level selection — tune per operation:**
```python
# Write: LOCAL_QUORUM (majority of replicas in local DC)
session.execute(statement.with_consistency_level(ConsistencyLevel.LOCAL_QUORUM))
# Read: LOCAL_ONE for high-throughput non-critical reads
# Use QUORUM only when read-after-write consistency is required
```

**Avoid `ALLOW FILTERING` in production queries:**
```sql
-- BAD: forces full table scan
SELECT * FROM events WHERE event_type = 'click' ALLOW FILTERING;
-- GOOD: create a dedicated table with event_type in the partition key
```
`ALLOW FILTERING` is a code smell that indicates the query does not match the table design.

**Use prepared statements for all parameterized queries:**
```python
stmt = session.prepare("INSERT INTO events (device_id, occurred_at, payload) VALUES (?, ?, ?)")
session.execute(stmt, [device_id, datetime.utcnow(), payload])
```
Prepared statements are parsed once per node and reused — significant overhead reduction at high throughput.

**Batch only for logged atomicity across partition updates — not for performance:**
```sql
-- LOGGED BATCH: atomic across multiple partitions (use rarely, Paxos overhead)
BEGIN BATCH
  INSERT INTO users_by_id ...;
  INSERT INTO users_by_email ...;
APPLY BATCH;
-- UNLOGGED BATCH to the same partition: fine for bulk same-partition writes
```
Multi-partition unlogged batches route to the coordinator, creating a hotspot — slower than individual statements.

**Tombstone accumulation:** Every `DELETE` and every TTL expiration creates a tombstone. Reads must scan past tombstones during the GC grace period. Monitor with `nodetool cfstats` — `Tombstone scanned` > 1000 per read is a warning.

## Security

**Authentication and authorization:**
```yaml
# cassandra.yaml
authenticator: PasswordAuthenticator
authorizer: CassandraAuthorizer
```
```sql
CREATE ROLE app WITH PASSWORD = 'secret' AND LOGIN = true;
GRANT SELECT, MODIFY ON KEYSPACE myapp TO app;
-- Revoke superuser from default 'cassandra' role in production
ALTER ROLE cassandra WITH SUPERUSER = false AND LOGIN = false;
```

**Encryption in transit (internode + client):**
```yaml
# cassandra.yaml
server_encryption_options:
  internode_encryption: all
  keystore: /etc/cassandra/keystore.jks
client_encryption_options:
  enabled: true
  keystore: /etc/cassandra/keystore.jks
  require_client_auth: false
```

**Encryption at rest:** Cassandra does not provide built-in encryption at rest. Use filesystem-level encryption (LUKS, AWS EBS encryption) or the DataStax Enterprise transparent data encryption extension.

**Network:** Never expose JMX (port 7199) or CQL native transport (9042) to public networks. Use security groups / firewall rules to restrict to application servers only.

## Testing

Use **Testcontainers** (Cassandra module) for integration tests:
```java
@Container
static CassandraContainer<?> cassandra = new CassandraContainer<>("cassandra:4.1")
    .withConfigurationOverride("cassandra-test");  // custom cassandra.yaml in resources

CqlSession session = CqlSession.builder()
    .addContactPoint(cassandra.getContactPoint())
    .withLocalDatacenter(cassandra.getLocalDatacenter())
    .build();
```
Apply schema migrations (using Cassandra Migrations or manual CQL) before each test class. Test both the `LOCAL_ONE` and `LOCAL_QUORUM` consistency paths. Verify tombstone behavior by explicitly deleting rows and checking that reads still return correct results after GC grace period simulation. Do not use `embedded-cassandra` libraries — they lag significantly behind the real Cassandra version and miss behavioral differences.

## Dos
- Model data tables query-first — write down every query the application needs, then design one table per query.
- Use time-bucketed partition keys (`(entity_id, bucket_date)`) for time-series data to bound partition size.
- Use `TimeWindowCompactionStrategy` (TWCS) for time-series tables with TTL — it minimizes read amplification and write overhead.
- Set `default_time_to_live` on all time-series tables to auto-expire old data and avoid manual deletes (tombstones).
- Use prepared statements for all CQL queries — reduces parse overhead and prevents injection.
- Use `LOCAL_QUORUM` for writes and reads that require strong consistency; use `LOCAL_ONE` for high-throughput read paths where eventual consistency is acceptable.
- Monitor partition sizes with `nodetool tablestats` and tombstone scan rates before performance degrades.

## Don'ts
- Don't use `ALLOW FILTERING` in production — it signals a table design mismatch; create a new table instead.
- Don't use `DELETE` in high-write-throughput paths for cleanup — accumulating tombstones degrade read performance; use TTL instead.
- Don't use multi-partition `UNLOGGED BATCH` for performance — it creates coordinator hotspots and is slower than individual statements.
- Don't use Cassandra secondary indexes on high-cardinality columns — they scatter queries across all nodes, negating partition locality.
- Don't store mutable counters in regular tables without using the `COUNTER` column type — concurrent increments on regular columns cause lost updates.
- Don't set `gc_grace_seconds = 0` without understanding tombstone implications — it risks bringing back deleted data on node repair.
- Don't use `ConsistencyLevel.ALL` in production — a single node being down makes all writes fail; use `QUORUM` or `LOCAL_QUORUM` for strong consistency.
