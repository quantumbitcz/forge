# TiDB Best Practices

## Overview
TiDB is a MySQL-compatible distributed SQL database providing horizontal scalability, strong consistency, and HTAP (Hybrid Transactional/Analytical Processing) capabilities. Use it for applications needing MySQL compatibility with automatic sharding, distributed transactions, and real-time analytics on transactional data. Avoid it for simple single-node workloads where MySQL/PostgreSQL suffice, or for pure OLAP where ClickHouse is more efficient.

## Architecture Patterns

**MySQL-compatible SQL:**
```sql
-- Standard MySQL syntax works
CREATE TABLE orders (
    id BIGINT AUTO_RANDOM PRIMARY KEY,
    user_id BIGINT NOT NULL,
    total DECIMAL(10,2) NOT NULL,
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_status (user_id, status)
);

-- Distributed transactions work transparently
BEGIN;
INSERT INTO orders (user_id, total) VALUES (123, 99.99);
UPDATE inventory SET stock = stock - 1 WHERE product_id = 456;
COMMIT;
```

**AUTO_RANDOM for distributed primary keys:**
```sql
-- AUTO_RANDOM avoids write hotspots (unlike AUTO_INCREMENT)
CREATE TABLE events (
    id BIGINT AUTO_RANDOM PRIMARY KEY,
    event_type VARCHAR(100),
    payload JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**TiFlash for real-time analytics (HTAP):**
```sql
-- Add TiFlash replica for columnar analytics
ALTER TABLE orders SET TIFLASH REPLICA 1;

-- OLAP queries automatically use TiFlash
SELECT DATE(created_at) AS day, SUM(total) AS revenue
FROM orders
WHERE created_at >= '2026-01-01'
GROUP BY day
ORDER BY day;
```

**Anti-pattern — using AUTO_INCREMENT in distributed mode: AUTO_INCREMENT creates write hotspots on a single TiKV region. Use AUTO_RANDOM for distributed writes.

## Configuration

```yaml
# TiDB cluster (tiup)
tiup playground --tag myapp --db 1 --pd 1 --kv 3 --tiflash 1

# Connection string (MySQL-compatible)
mysql://app:pass@tidb.internal:4000/mydb?charset=utf8mb4
```

## Performance

**EXPLAIN ANALYZE for distributed plans:**
```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 123 ORDER BY created_at DESC LIMIT 20;
```
Look for: `TableFullScan` (missing index), cross-region reads, coprocessor timeouts.

**Batch DML for bulk operations:**
```sql
-- TiDB processes batch DML more efficiently than row-by-row
INSERT INTO events (type, payload) VALUES ('a', '{}'), ('b', '{}'), ...;
```

**Coprocessor pushdown:** TiDB pushes predicates and aggregations to TiKV — design queries to maximize pushdown for reduced network overhead.

## Security

**Least-privilege users:**
```sql
CREATE USER 'app'@'%' IDENTIFIED BY '...';
GRANT SELECT, INSERT, UPDATE, DELETE ON mydb.* TO 'app'@'%';
```

**TLS encryption:** Enable TLS for client connections and configure `require_secure_transport`.

**SQL injection prevention:** Use parameterized queries — TiDB is MySQL-compatible, so all MySQL driver parameterization works.

## Testing

Use **Testcontainers** or `tiup playground` for integration tests:
```bash
tiup playground --tag test --db 1 --pd 1 --kv 1
```

Test transaction retry logic explicitly — optimistic transaction conflicts are more common than in single-node MySQL. Verify TiFlash queries return correct results for analytics workloads.

## Dos
- Use `AUTO_RANDOM` instead of `AUTO_INCREMENT` for primary keys — avoids write hotspots.
- Use TiFlash replicas for analytics queries — keeps OLTP and OLAP workloads separated.
- Use `EXPLAIN ANALYZE` to understand distributed query execution plans.
- Use TiDB Dashboard for cluster monitoring and slow query analysis.
- Use `tiup` for cluster deployment and management.
- Implement transaction retry logic — optimistic transactions may need retries under contention.
- Use MySQL-compatible drivers and ORMs — TiDB works with existing MySQL tooling.

## Don'ts
- Don't use `AUTO_INCREMENT` as primary key in high-write tables — it creates hotspots.
- Don't ignore transaction model differences — TiDB uses optimistic by default (configurable to pessimistic).
- Don't assume MySQL feature parity — some features (stored procedures, triggers) have limitations.
- Don't skip TiFlash for analytics — running OLAP on TiKV impacts OLTP performance.
- Don't use TiDB for tiny datasets — the distributed overhead isn't justified for small workloads.
- Don't ignore Region distribution — monitor hotspot Regions in TiDB Dashboard.
- Don't set `tidb_gc_life_time` too long — it increases storage and affects GC performance.
