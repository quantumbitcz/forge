# CockroachDB Best Practices

## Overview
CockroachDB is a distributed SQL database providing horizontal scalability, strong consistency (serializable isolation), and automatic geo-replication. Use it for globally distributed applications, multi-region deployments, and workloads needing PostgreSQL compatibility with automatic sharding. Avoid CockroachDB for single-node workloads where PostgreSQL suffices (lower operational complexity), write-heavy analytics (use ClickHouse), or when you need very low single-query latency without geographic locality.

## Architecture Patterns

**PostgreSQL-compatible SQL with automatic sharding:**
```sql
-- Standard SQL — CockroachDB is wire-compatible with PostgreSQL
CREATE TABLE orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id),
  total DECIMAL(10,2) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  region STRING NOT NULL
);

-- Hash-sharded index for sequential write hotspots
CREATE INDEX idx_orders_created ON orders(created_at) USING HASH;
```

**Multi-region table localities:**
```sql
-- Pin data to the region where it's most accessed
ALTER TABLE users SET LOCALITY REGIONAL BY ROW;
ALTER TABLE users ADD COLUMN crdb_region crdb_internal_region AS (
  CASE WHEN country IN ('US', 'CA') THEN 'us-east1'
       WHEN country IN ('DE', 'FR') THEN 'europe-west1'
       ELSE 'us-east1'
  END
) STORED;
```

**Change data capture (CDC) for event sourcing:**
```sql
CREATE CHANGEFEED FOR TABLE orders INTO 'kafka://broker:9092'
  WITH updated, resolved='10s', schema_change_policy='backfill';
```

**Anti-pattern — secondary indexes on high-cardinality sequential keys:** Auto-incrementing or timestamp-based indexes create write hotspots on a single range. Use `USING HASH` or UUID primary keys.

## Configuration

**Connection string:**
```
postgresql://app:pass@lb.cockroachdb.internal:26257/mydb?sslmode=verify-full&sslrootcert=/certs/ca.crt&application_name=myapp
```

**Cluster settings (production):**
```sql
SET CLUSTER SETTING kv.rangefeed.enabled = true;        -- required for CDC
SET CLUSTER SETTING server.time_until_store_dead = '5m'; -- faster node detection
SET CLUSTER SETTING sql.defaults.idle_in_transaction_session_timeout = '30s';
```

**Session settings:**
```sql
SET statement_timeout = '30s';
SET idle_in_transaction_session_timeout = '60s';
```

## Performance

**EXPLAIN ANALYZE for distributed query plans:**
```sql
EXPLAIN ANALYZE (DISTSQL) SELECT * FROM orders WHERE user_id = $1 ORDER BY created_at DESC LIMIT 20;
```
Look for: `full scan` (missing index), cross-range reads, distributed joins across regions.

**Batch INSERTs (multi-row):**
```sql
INSERT INTO events (id, type, payload) VALUES
  ($1, $2, $3), ($4, $5, $6), ($7, $8, $9);
-- CockroachDB batches 128 rows automatically; explicit batching reduces round trips
```

**Follower reads for stale-tolerant queries:**
```sql
-- Read from nearest replica (slightly stale, but low latency)
SELECT * FROM products AS OF SYSTEM TIME follower_read_timestamp() WHERE category = $1;
```

**Transaction retry loop (required for serializable isolation):**
```go
for {
    tx, err := db.Begin()
    if err != nil { return err }
    _, err = tx.Exec("UPDATE accounts SET balance = balance - $1 WHERE id = $2", amount, fromId)
    if err != nil {
        tx.Rollback()
        if isCRDBRetryError(err) { continue }
        return err
    }
    err = tx.Commit()
    if isCRDBRetryError(err) { continue }
    return err
}
```

## Security

**Certificate-based authentication (recommended over password):**
```bash
cockroach cert create-client app --certs-dir=/certs --ca-key=/ca/ca.key
```

**Role-based access:**
```sql
CREATE USER app_user WITH PASSWORD '...';
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE orders TO app_user;
REVOKE ALL ON DATABASE defaultdb FROM public;
```

**Encryption at rest:** Enabled by default in CockroachDB Cloud. For self-hosted, use `--enterprise-encryption` flag with AES-256.

**Audit logging:**
```sql
ALTER TABLE users AUDIT SET READ WRITE;
```

## Testing

Use **Testcontainers** with CockroachDB:
```java
@Container
static CockroachContainer crdb = new CockroachContainer("cockroachdb/cockroach:v24.1.0")
    .withCommand("start-single-node --insecure");
```

For unit tests, CockroachDB's PostgreSQL compatibility means most PostgreSQL test utilities work. Test transaction retry logic explicitly — serializable isolation produces more retryable errors than read-committed databases.

## Dos
- Use UUID primary keys (`gen_random_uuid()`) — sequential IDs create write hotspots on a single range.
- Implement transaction retry loops — CockroachDB's serializable isolation can abort transactions that must retry.
- Use `AS OF SYSTEM TIME` for read-heavy dashboards — follower reads reduce cross-region latency.
- Prefer multi-row INSERTs and batch operations to reduce distributed consensus overhead per statement.
- Use hash-sharded indexes for timestamp-based columns to avoid range hotspots.
- Monitor via the built-in DB Console (`/_status/vars`) and integrate with Prometheus.
- Use `IMPORT INTO` or `COPY FROM` for bulk data loading — orders of magnitude faster than row-by-row inserts.

## Don'ts
- Don't use auto-incrementing `SERIAL` IDs — they create write hotspots; use UUID or `unique_rowid()`.
- Don't ignore transaction retry errors — they're expected in serializable isolation, not bugs.
- Don't assume single-region latency for multi-region deployments — cross-region consensus adds latency.
- Don't use `SELECT FOR UPDATE` as a general locking mechanism — CockroachDB's serializable isolation handles most concurrency without explicit locks.
- Don't create too many secondary indexes — each index is a distributed range that adds write amplification.
- Don't skip `EXPLAIN ANALYZE (DISTSQL)` for new queries — distributed plans can behave differently from single-node PostgreSQL.
- Don't use CockroachDB for OLAP workloads — it's optimized for OLTP; use ClickHouse or a data warehouse for analytics.
