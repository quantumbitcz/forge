# PostgreSQL Best Practices

## Overview
PostgreSQL is an ACID-compliant relational database with strong support for complex queries, JSON documents, full-text search, and advanced indexing. Use it as your default choice for transactional workloads, relational data, or when you need JSONB flexibility alongside structured schema. Avoid PostgreSQL when you need extreme write throughput at petabyte scale (consider ClickHouse or Cassandra) or when a simple embedded store suffices (consider SQLite).

## Architecture Patterns

**Connection pooling via PgBouncer (transaction mode):**
```ini
[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 20
server_idle_timeout = 600
```
Never let application threads hold idle connections — PgBouncer transaction mode multiplexes thousands of clients onto a small server pool.

**Partitioning large tables by range:**
```sql
CREATE TABLE events (
  id BIGSERIAL,
  occurred_at TIMESTAMPTZ NOT NULL,
  payload JSONB
) PARTITION BY RANGE (occurred_at);

CREATE TABLE events_2026_03 PARTITION OF events
  FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
```

**JSONB for semi-structured data:**
```sql
-- GIN index for arbitrary key lookup
CREATE INDEX idx_events_payload ON events USING GIN (payload jsonb_path_ops);
-- Query
SELECT * FROM events WHERE payload @> '{"type": "purchase"}';
```

**Advisory locks for distributed coordination:**
```sql
-- Acquire session-level lock (non-blocking)
SELECT pg_try_advisory_lock(hashtext('job:invoice-batch'));
```

**Anti-pattern — SELECT * with no LIMIT on wide tables:** Full row scans with large row widths cause excessive buffer cache eviction. Always project needed columns and paginate with keyset pagination (`WHERE id > $last_id LIMIT 100`), not `OFFSET`.

## Configuration

**Development (`postgresql.conf` overrides):**
```conf
shared_buffers = 256MB
work_mem = 16MB
maintenance_work_mem = 128MB
log_min_duration_statement = 200ms
```

**Production tuning (starting points, tune per workload):**
```conf
shared_buffers = 25% of RAM          # e.g. 8GB on 32GB host
effective_cache_size = 75% of RAM
work_mem = 4MB                        # per sort/hash; multiply by max_connections
maintenance_work_mem = 1GB
max_connections = 100                 # keep low; use PgBouncer in front
wal_level = replica
max_wal_senders = 5
checkpoint_completion_target = 0.9
random_page_cost = 1.1               # for SSD storage
```

**Environment variables (app side):**
```
DATABASE_URL=postgres://user:pass@pgbouncer:5432/mydb?sslmode=require&application_name=myapp
```

## Performance

**EXPLAIN ANALYZE before shipping any new query:**
```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT ...;
```
Look for: `Seq Scan` on large tables, high `Buffers: shared hit/read` ratio, nested loop with large outer rows.

**Index selection:**
- B-tree: equality and range (`=`, `<`, `>`, `BETWEEN`)
- GIN: array containment, JSONB, full-text (`@>`, `@@`)
- GiST: geometric/range types, `&&` overlap
- Partial index: `CREATE INDEX ... WHERE deleted_at IS NULL` — dramatically smaller index for soft-delete patterns

**Avoid N+1 with CTEs or lateral joins:**
```sql
WITH ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC) rn
  FROM orders
)
SELECT * FROM ranked WHERE rn = 1;
```

**VACUUM and autovacuum:** Dead tuples from MVCC bloat tables. Ensure `autovacuum` is enabled (default). Run `VACUUM ANALYZE` manually after bulk loads. Monitor with `pg_stat_user_tables.n_dead_tup`.

**Connection overhead:** Each PostgreSQL process costs ~5-10 MB. Never size `max_connections` for direct app traffic — always proxy through PgBouncer.

## Security

**Least-privilege roles:**
```sql
CREATE ROLE app_user LOGIN PASSWORD '...' NOSUPERUSER NOCREATEDB NOCREATEROLE;
GRANT CONNECT ON DATABASE mydb TO app_user;
GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
```

**Parameterized queries (never string-interpolate SQL):**
```python
cursor.execute("SELECT * FROM users WHERE email = %s", (email,))
```

**Encryption in transit:** Always set `sslmode=require` (or `verify-full` with CA cert) in connection strings. Never use `sslmode=disable` in production.

**Secrets:** Store credentials in environment variables or a secrets manager — never in `postgresql.conf` or application config files.

**Row-level security for multi-tenancy:**
```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON orders
  USING (tenant_id = current_setting('app.tenant_id')::uuid);
```

## Testing

Use **Testcontainers** for integration tests — spin up a real PostgreSQL instance per test suite:
```java
@Container
static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
    .withDatabaseName("testdb")
    .withUsername("test")
    .withPassword("test");
```
Run migrations (Flyway/Liquibase) inside the container before tests. For unit tests of query logic, use an in-process schema with `@Transactional` rollback. Never mock the database layer for query correctness tests — real SQL is the only reliable test.

## Dos
- Use `BIGSERIAL` or `UUID` (v7 for sortability) as primary keys.
- Always run `EXPLAIN ANALYZE` on queries touching > 10k rows before merging.
- Prefer partial indexes and GIN indexes over full-column B-tree indexes for JSONB and sparse conditions.
- Use `COPY` for bulk inserts (10-100x faster than multi-row `INSERT`).
- Set `statement_timeout` and `lock_timeout` per session to prevent runaway queries and lock pile-ups.
- Automate schema migrations (Flyway or Liquibase) — never apply DDL by hand in production.
- Enable `pg_stat_statements` extension to identify slow queries in production.

## Don'ts
- Don't use `OFFSET` for deep pagination — it scans and discards rows; use keyset pagination instead.
- Don't store passwords or secrets as plaintext in any table — hash with `pgcrypto` or at the application layer.
- Don't use `SELECT *` in application queries — it prevents index-only scans and couples code to schema changes.
- Don't hold long-running transactions during user-facing requests — they block VACUUM and cause lock contention.
- Don't create indexes blindly — each index slows writes and consumes storage; validate with `EXPLAIN ANALYZE`.
- Don't use `SERIAL` (32-bit) for high-volume tables — use `BIGSERIAL`; exhausted sequences cause outages.
- Don't run DDL (ALTER TABLE, DROP INDEX) during peak traffic without first testing lock impact; use `CREATE INDEX CONCURRENTLY` instead.
