# ClickHouse Best Practices

## Overview
ClickHouse is a column-oriented OLAP database designed for high-throughput analytical queries over large datasets (billions of rows). Use it for product analytics, time-series event data, log aggregation, and business intelligence workloads where query latency matters more than single-row lookup speed. Avoid ClickHouse for OLTP (high-frequency single-row reads/writes), transactional workloads requiring ACID multi-row updates, or datasets smaller than a few million rows where PostgreSQL suffices.

## Architecture Patterns

**MergeTree engine family — choose the right variant:**
```sql
-- Standard analytics table
CREATE TABLE events (
    event_date   Date           CODEC(Delta, ZSTD),
    event_time   DateTime64(3)  CODEC(Delta, ZSTD),
    user_id      UInt64,
    event_type   LowCardinality(String),
    properties   String
) ENGINE = MergeTree()
  PARTITION BY toYYYYMM(event_date)
  ORDER BY (event_type, user_id, event_time)
  TTL event_date + INTERVAL 2 YEAR DELETE;

-- Deduplication with ReplacingMergeTree
ENGINE = ReplacingMergeTree(updated_at)
  ORDER BY (user_id, entity_id)   -- dedup key

-- Aggregated rollups with AggregatingMergeTree
ENGINE = AggregatingMergeTree()
  ORDER BY (toDate(event_time), event_type)
```

**Materialized views for pre-aggregated rollups:**
```sql
CREATE MATERIALIZED VIEW daily_revenue_mv
ENGINE = SummingMergeTree()
ORDER BY (day, product_id)
AS SELECT
    toDate(event_time) AS day,
    product_id,
    sumState(amount) AS revenue
FROM orders
GROUP BY day, product_id;
```
Materialized views update incrementally on insert — they are the primary tool for pre-computing expensive aggregations.

**Partition management for time-series retention:**
```sql
-- Drop entire partition (instant, no row-level delete cost)
ALTER TABLE events DROP PARTITION '202501';
-- Move cold partitions to slower storage tier
ALTER TABLE events MOVE PARTITION '202401' TO DISK 'cold_disk';
```

**ReplicatedMergeTree for HA:**
```sql
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/events', '{replica}')
  PARTITION BY toYYYYMM(event_date)
  ORDER BY (user_id, event_time);
```

**Anti-pattern — querying on non-primary-key columns without a skip index:** ClickHouse reads data in granules (8192 rows by default). Without a sparse index or Bloom filter, a `WHERE email = '...'` on a non-ORDER-BY column scans the entire table.

## Configuration

**config.xml tuning (production):**
```xml
<max_threads>16</max_threads>                  <!-- = CPU cores -->
<max_memory_usage>20000000000</max_memory_usage> <!-- 20 GB per query -->
<max_bytes_before_external_group_by>10000000000</max_bytes_before_external_group_by>
<max_bytes_before_external_sort>10000000000</max_bytes_before_external_sort>
<merge_tree>
    <max_bytes_to_merge_at_max_space_in_pool>161061273600</max_bytes_to_merge_at_max_space_in_pool>
    <number_of_free_entries_in_pool_to_lower_max_size_of_merge>8</number_of_free_entries_in_pool_to_lower_max_size_of_merge>
</merge_tree>
```

**users.xml — restrict query complexity:**
```xml
<max_execution_time>60</max_execution_time>
<max_rows_to_read>1000000000</max_rows_to_read>
<readonly>1</readonly>  <!-- for read-only analytics users -->
```

**Codec selection for column compression:**
```sql
-- Timestamps: Delta + ZSTD (high compression for monotonic sequences)
event_time DateTime64(3) CODEC(Delta(4), ZSTD(3)),
-- High-cardinality IDs: ZSTD only
user_id UInt64 CODEC(ZSTD(1)),
-- Low-cardinality strings: LowCardinality (dictionary encoding, automatic)
status LowCardinality(String)
```

## Performance

**Batch inserts — never insert single rows:**
```python
# Insert in batches of 10,000–100,000 rows
client.insert("events", rows, column_names=["event_time", "user_id", "event_type"])
# For streaming ingestion, buffer at least 1 second of events per batch
```
Each insert creates a part on disk. Hundreds of tiny inserts create thousands of parts, overwhelming the merge background process and causing `Too many parts` errors.

**ORDER BY key design — most common filter/group columns first:**
```sql
-- If most queries filter by (event_type, user_id), put those first
ORDER BY (event_type, user_id, event_time)
-- ClickHouse skips granules that don't match the prefix
```

**Skip indexes for non-primary-key filtering:**
```sql
INDEX idx_session_id session_id TYPE bloom_filter(0.01) GRANULARITY 4
```

**Use `PREWHERE` instead of `WHERE` for selective conditions on large tables:**
```sql
-- ClickHouse evaluates PREWHERE before reading other columns
SELECT count() FROM events PREWHERE event_type = 'purchase' WHERE amount > 100;
```

**Asynchronous inserts (ClickHouse Cloud / 22.8+):**
```sql
SET async_insert = 1, wait_for_async_insert = 0;
-- Client-side batching is still preferred; async inserts are a safety net
```

## Security

**User and role management:**
```sql
CREATE USER analytics IDENTIFIED WITH sha256_password BY 'secret';
CREATE ROLE read_only;
GRANT SELECT ON analytics_db.* TO read_only;
GRANT read_only TO analytics;
```

**Network access:** Bind HTTP interface (8123) and native protocol (9000) to internal IPs only. Use TLS for both protocols in production:
```xml
<https_port>8443</https_port>
<tcp_ssl_port>9440</tcp_ssl_port>
```

**Row-level policies for multi-tenant analytics:**
```sql
CREATE ROW POLICY tenant_filter ON events
  FOR SELECT USING tenant_id = currentUser()
  TO analytics;
```

**Secrets:** Never embed credentials in `ON CLUSTER` DDL statements — use `clickhouse-keeper` or HashiCorp Vault for secret injection.

## Testing

ClickHouse does not have an official embedded mode. Use **Testcontainers** for integration tests:
```java
@Container
static ClickHouseContainer clickhouse = new ClickHouseContainer("clickhouse/clickhouse-server:24.3");

ClickHouseClient client = ClickHouseClient.newInstance(
    ClickHouseProtocol.HTTP,
    clickhouse.getClickHouseNode()
);
```

For unit tests of aggregation logic, test against a Testcontainers instance with seeded data. Verify both correctness of results and that queries use expected indexes (`EXPLAIN indexes = 1 SELECT ...`). Test partition drops and TTL expiration using `SYSTEM STOP/START MERGES` to control merge timing.

## Dos
- Always batch inserts — aim for 10,000-100,000 rows per insert; use a buffer (Kafka, in-memory queue) to accumulate batches before flushing.
- Design the `ORDER BY` key to match the most common query filters — it is the primary index and determines read efficiency.
- Use `LowCardinality(String)` for columns with < 10,000 distinct values — it enables dictionary encoding and dramatically reduces memory usage.
- Apply `CODEC(Delta, ZSTD)` to timestamp and monotonic numeric columns for 5-10x compression improvement.
- Use partitioning by month or week and drop old partitions for retention — it is instant and does not fragment active data.
- Use materialized views with `AggregatingMergeTree` or `SummingMergeTree` for pre-computed rollups instead of querying raw tables for dashboards.
- Monitor `system.parts` for part count — more than ~300 active parts per table is a warning sign of too-frequent small inserts.

## Don'ts
- Don't insert single rows — each insert creates a part; thousands of parts overwhelm background merges and cause query slowdowns.
- Don't use `DELETE` or `UPDATE` for routine data modification — ClickHouse mutations are asynchronous, non-transactional, and rewrite entire parts; model data to avoid them.
- Don't place high-cardinality columns (user_id, UUID) as the first `ORDER BY` key unless every query filters by that column — it negates granule pruning for other filters.
- Don't use `JOIN` with large right-hand tables in ad-hoc queries without testing memory usage — ClickHouse loads the right table into memory; use `IN (subquery)` or pre-aggregate instead.
- Don't run ClickHouse without replication in production — a single-node failure loses data permanently since there is no WAL-based recovery for OLAP engines.
- Don't query `system.query_log` or `information_schema` tables in hot paths — they are non-optimized metadata tables.
- Don't use `String` type for columns with a small fixed set of values — use `Enum8` or `LowCardinality(String)` for up to 10,000 distinct values.
