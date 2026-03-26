# MariaDB Best Practices

## Overview
MariaDB is a community-driven MySQL fork with enhanced features: system-versioned tables, columnar storage (ColumnStore), Oracle-compatible PL/SQL mode, and improved optimizer. Use it for web applications, SaaS backends, and workloads that benefit from MySQL compatibility with additional enterprise features. Avoid MariaDB when you need the MySQL ecosystem exactly (Oracle-maintained connectors, MySQL Shell, HeatWave), or when PostgreSQL's advanced type system and extensibility better fit your use case.

## Architecture Patterns

**Connection pooling via ProxySQL or MaxScale:**
```ini
# MaxScale configuration
[ReadWriteSplit]
type=service
router=readwritesplit
servers=db1,db2,db3
user=maxscale
password=...
```
MariaDB MaxScale provides read/write splitting, connection pooling, and query routing. For simpler setups, use application-level pooling (HikariCP, SQLAlchemy pool).

**Galera Cluster for multi-master replication:**
```ini
# my.cnf
[galera]
wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so
wsrep_cluster_address="gcomm://node1,node2,node3"
wsrep_sst_method=mariabackup
```

**System-versioned tables (temporal queries):**
```sql
CREATE TABLE products (
  id INT PRIMARY KEY,
  name VARCHAR(100),
  price DECIMAL(10,2)
) WITH SYSTEM VERSIONING;

-- Query historical data
SELECT * FROM products FOR SYSTEM_TIME AS OF '2026-01-15 10:00:00';
SELECT * FROM products FOR SYSTEM_TIME BETWEEN '2026-01-01' AND '2026-03-01';
```

**Sequences (MariaDB 10.3+):**
```sql
CREATE SEQUENCE order_seq START WITH 1 INCREMENT BY 1;
INSERT INTO orders (id, ...) VALUES (NEXT VALUE FOR order_seq, ...);
```

**Anti-pattern — mixing storage engines within a transaction:** InnoDB is transactional; MyISAM is not. A transaction touching both engines silently loses atomicity on MyISAM tables.

## Configuration

**Development (`my.cnf`):**
```ini
[mysqld]
innodb_buffer_pool_size = 256M
innodb_log_file_size = 128M
slow_query_log = ON
long_query_time = 0.5
```

**Production tuning:**
```ini
[mysqld]
innodb_buffer_pool_size = 24G          # 70-80% of RAM
innodb_buffer_pool_instances = 8       # 1 per GB of pool (up to 64)
innodb_log_file_size = 2G
innodb_flush_log_at_trx_commit = 1     # full ACID durability
innodb_flush_method = O_DIRECT
max_connections = 200
thread_pool_size = 16
query_cache_type = 0                   # disabled — stale in write-heavy workloads
```

**Connection string:**
```
mysql://app:pass@maxscale:3306/mydb?charset=utf8mb4&parseTime=true&loc=UTC&timeout=5s
```

## Performance

**EXPLAIN and optimizer trace:**
```sql
EXPLAIN EXTENDED SELECT ...;
ANALYZE TABLE orders;
-- Detailed optimizer decisions
SET optimizer_trace = 'enabled=on';
SELECT ...;
SELECT * FROM information_schema.optimizer_trace;
```

**Index hints when optimizer misses:**
```sql
SELECT * FROM orders FORCE INDEX (idx_user_status) WHERE user_id = ? AND status = 'active';
```

**Window functions (MariaDB 10.2+):**
```sql
SELECT user_id, amount,
  SUM(amount) OVER (PARTITION BY user_id ORDER BY created_at) AS running_total
FROM orders;
```

**ColumnStore for analytics (MariaDB ColumnStore engine):**
```sql
CREATE TABLE analytics_events (
  event_time DATETIME,
  event_type VARCHAR(50),
  payload TEXT
) ENGINE=ColumnStore;
```

## Security

**User privileges (least-privilege):**
```sql
CREATE USER 'app'@'10.0.%' IDENTIFIED BY '...';
GRANT SELECT, INSERT, UPDATE, DELETE ON mydb.* TO 'app'@'10.0.%';
FLUSH PRIVILEGES;
```

**TLS enforcement:**
```ini
[mysqld]
ssl_cert = /etc/mysql/server-cert.pem
ssl_key = /etc/mysql/server-key.pem
require_secure_transport = ON
```

**Parameterized queries:**
```python
cursor.execute("SELECT * FROM users WHERE email = %s", (email,))
```

**Data-at-rest encryption (InnoDB tablespace encryption):**
```sql
ALTER TABLE users ENCRYPTED=YES ENCRYPTION_KEY_ID=1;
```

## Testing

Use **Testcontainers** for integration tests:
```java
@Container
static MariaDBContainer<?> mariadb = new MariaDBContainer<>("mariadb:11")
    .withDatabaseName("testdb")
    .withUsername("test")
    .withPassword("test");
```

For lightweight tests, use embedded MariaDB4j or MySQL-compatible in-memory databases. Run Flyway/Liquibase migrations inside the container before tests. Test Galera-specific behavior (deadlocks, certification conflicts) with a 3-node Docker Compose cluster.

## Dos
- Use InnoDB for all transactional tables — it's the default since MariaDB 10.2.
- Use `utf8mb4` charset everywhere — `utf8` in MySQL/MariaDB is only 3-byte and truncates emoji/CJK.
- Leverage system-versioned tables for audit trails instead of building custom audit trigger logic.
- Use `ON DUPLICATE KEY UPDATE` for upsert patterns — prefer it over `REPLACE INTO` which deletes and re-inserts rows.
- Monitor with `SHOW GLOBAL STATUS` and `performance_schema` — track `Innodb_buffer_pool_hit_rate`, `Threads_running`, `Slow_queries`.
- Use MariaDB Backup (`mariabackup`) for hot backups — `mysqldump` locks tables and is unsuitable for large databases.
- Set `innodb_strict_mode = ON` to catch silent data truncation.

## Don'ts
- Don't use MyISAM for anything that needs transactions, crash recovery, or concurrent writes.
- Don't rely on `query_cache` in write-heavy workloads — it's invalidated on every write and causes mutex contention.
- Don't use `FLOAT`/`DOUBLE` for monetary values — use `DECIMAL(precision, scale)`.
- Don't skip `ANALYZE TABLE` after bulk loads — stale statistics cause the optimizer to choose bad plans.
- Don't use `utf8` charset — always use `utf8mb4` for full Unicode support.
- Don't expose port 3306 to the internet — use VPC/private network + TLS + IP allowlisting.
- Don't use `root` for application connections — create dedicated users with minimal privileges.
