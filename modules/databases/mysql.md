# MySQL Best Practices

## Overview
MySQL (InnoDB engine) is a mature, widely-supported relational database suited for web applications, OLTP workloads, and read-heavy systems. Use it when your stack or hosting environment strongly favors MySQL (e.g., existing LAMP infrastructure, PlanetScale, RDS MySQL). Prefer PostgreSQL for complex queries, JSONB, or advanced indexing needs. Avoid MySQL for analytics or write-heavy append-only workloads.

## Architecture Patterns

**Always use InnoDB storage engine:**
```sql
CREATE TABLE orders (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```
MyISAM lacks transactions and foreign keys — never use it for application tables.

**Covering index for read-heavy queries:**
```sql
-- Query: SELECT status, total FROM orders WHERE user_id = ? ORDER BY created_at DESC
CREATE INDEX idx_orders_user_covering
  ON orders (user_id, created_at DESC, status, total);
```
InnoDB always appends the primary key to secondary indexes — include only the extra columns you need.

**Replication with GTID (Global Transaction Identifiers):**
```ini
# Primary
gtid_mode = ON
enforce_gtid_consistency = ON
log_bin = mysql-bin
binlog_format = ROW

# Replica
gtid_mode = ON
enforce_gtid_consistency = ON
relay_log_recovery = ON
```
GTID-based replication enables safe failover and point-in-time replica promotion.

**Partitioning by range for time-series data:**
```sql
ALTER TABLE events PARTITION BY RANGE (YEAR(created_at)) (
  PARTITION p2025 VALUES LESS THAN (2026),
  PARTITION p2026 VALUES LESS THAN (2027),
  PARTITION pFuture VALUES LESS THAN MAXVALUE
);
```

**Anti-pattern — implicit type coercion in WHERE:** `WHERE user_id = '123'` on an integer column causes a full table scan because MySQL coerces every row. Always match parameter types to column types.

## Configuration

**Development (`my.cnf` / `my.ini`):**
```ini
[mysqld]
innodb_buffer_pool_size = 256M
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 0.2
```

**Production tuning (starting points):**
```ini
[mysqld]
innodb_buffer_pool_size = 70-80% of RAM   # most important knob
innodb_buffer_pool_instances = 8           # one per GB of buffer pool up to 8
innodb_log_file_size = 2G
innodb_flush_log_at_trx_commit = 1         # ACID; use 2 only for non-critical data
innodb_flush_method = O_DIRECT
max_connections = 200                      # pair with a connection pool (ProxySQL)
thread_cache_size = 50
query_cache_size = 0                       # disable; query cache causes mutex contention
character_set_server = utf8mb4
collation_server = utf8mb4_unicode_ci
```

**Connection pool (application side — HikariCP example):**
```yaml
spring.datasource.hikari.maximum-pool-size: 20
spring.datasource.hikari.connection-timeout: 3000
spring.datasource.hikari.idle-timeout: 600000
```

## Performance

**Use `EXPLAIN FORMAT=JSON` to analyze query plans:**
```sql
EXPLAIN FORMAT=JSON SELECT u.id, COUNT(o.id)
FROM users u LEFT JOIN orders o ON u.id = o.user_id
WHERE u.active = 1 GROUP BY u.id;
```
Look for `"access_type": "ALL"` (full table scan), `"rows_examined_per_scan"` > 1000 without matching `key`.

**Index merge is a warning sign:** MySQL sometimes merges two indexes instead of using one composite index. If you see `type: index_merge` in EXPLAIN, create a composite index instead.

**Batch inserts over single-row inserts:**
```sql
INSERT INTO events (user_id, type, occurred_at) VALUES
  (1, 'click', NOW()), (2, 'click', NOW()), (3, 'purchase', NOW());
```
Single-row inserts in a loop are 10-50x slower due to per-statement commit overhead.

**Read replicas for reporting queries:** Route analytical queries to a replica via the connection pool — prevents read queries from blocking InnoDB buffer pool pages needed by writes.

**Avoid `SELECT COUNT(*)` on large tables without an indexed `WHERE` clause** — InnoDB does not maintain an exact row count; it scans the smallest secondary index.

## Security

**Least-privilege user:**
```sql
CREATE USER 'app'@'%' IDENTIFIED BY '...' REQUIRE SSL;
GRANT SELECT, INSERT, UPDATE, DELETE ON mydb.* TO 'app'@'%';
FLUSH PRIVILEGES;
```

**Parameterized queries (prevents SQL injection):**
```python
cursor.execute("SELECT * FROM users WHERE email = %s AND tenant_id = %s", (email, tenant_id))
```

**Encrypt data at rest:** Enable InnoDB tablespace encryption (`innodb_encrypt_tables=ON`) for sensitive PII. Use TLS (`--require_secure_transport=ON`) for all connections.

**Remove anonymous users and test database after installation:**
```sql
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
```

## Testing

Use **Testcontainers** for reliable integration tests:
```java
@Container
static MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.0")
    .withDatabaseName("testdb")
    .withUsername("test")
    .withPassword("test")
    .withCommand("--character-set-server=utf8mb4", "--collation-server=utf8mb4_unicode_ci");
```
Run Flyway/Liquibase migrations inside the container before each test class. Use `@Transactional` rollback for test isolation within a suite. Never use H2 in MySQL-compatibility mode — it misses too many behavioral differences (character sets, strict mode, JSON functions).

## Dos
- Always use `utf8mb4` charset and `utf8mb4_unicode_ci` collation — `utf8` in MySQL is a broken 3-byte subset that can't store emoji or some CJK characters.
- Use `BIGINT UNSIGNED AUTO_INCREMENT` for primary keys on high-volume tables.
- Enable `sql_mode = STRICT_TRANS_TABLES` to prevent silent data truncation.
- Use `DATETIME(6)` for microsecond timestamp precision; use `TIMESTAMP` only when you need automatic timezone conversion.
- Monitor slow query log regularly; tune or add indexes for queries exceeding your SLA threshold.
- Use `pt-online-schema-change` or `gh-ost` for DDL on large tables in production to avoid locking.
- Use `SHOW ENGINE INNODB STATUS` and Performance Schema to diagnose lock waits and deadlocks.

## Don'ts
- Don't use `utf8` charset — use `utf8mb4`; `utf8` silently truncates 4-byte characters causing data loss.
- Don't store IP addresses as `VARCHAR` — use `INET6` or `INT UNSIGNED` (`INET_ATON`) for efficient range queries.
- Don't use `ENUM` for status fields that may grow — adding values requires an ALTER TABLE; use a `VARCHAR` or a lookup table instead.
- Don't use MySQL for full-text search in production — MyISAM FULLTEXT and InnoDB FULLTEXT are limited; use Elasticsearch or Typesense.
- Don't ignore deadlock warnings in application logs — deadlocks mean overlapping lock acquisition order; fix by consistent lock ordering or shorter transactions.
- Don't set `innodb_flush_log_at_trx_commit = 0` on production — it can lose up to 1 second of committed transactions on crash.
- Don't rely on implicit commits — always use explicit `BEGIN` / `COMMIT` / `ROLLBACK` in multi-statement transactions.
