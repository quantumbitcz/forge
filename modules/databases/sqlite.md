# SQLite Best Practices

## Overview
SQLite is a serverless, single-file relational database engine. Use it for embedded applications, mobile apps (iOS/Android), CLI tools, local development databases, and test fixtures. It is the right choice when the database and application run on the same machine and you need zero administration. Avoid SQLite for multi-writer server applications, workloads exceeding ~100 concurrent writers, or datasets requiring fine-grained user access control.

## Architecture Patterns

**Enable WAL mode (Write-Ahead Logging) immediately after opening:**
```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;  -- safe with WAL; FULL is redundant
```
WAL allows concurrent readers alongside a single writer. Default journal mode serializes all access including reads, causing read starvation under write load.

**Foreign keys are off by default — always enable:**
```sql
PRAGMA foreign_keys = ON;
```
This pragma must be set per connection. Without it, referential integrity is silently unenforced.

**Single-writer enforcement — batch writes in transactions:**
```python
with db:  # auto-commits on success, rolls back on exception
    for row in rows:
        db.execute("INSERT INTO events VALUES (?, ?, ?)", row)
```
Each individual `INSERT` outside a transaction is its own fsync. Wrapping 1000 inserts in one transaction is 100-1000x faster.

**Schema versioning with `user_version`:**
```sql
PRAGMA user_version = 5;  -- increment on each migration
```
Read at startup to determine which migrations to apply. Simpler than a migrations table for embedded apps.

**Anti-pattern — opening multiple write connections from separate processes:** SQLite uses file-level locking. Two processes writing simultaneously causes `SQLITE_BUSY` / `SQLITE_LOCKED` errors. Use a single writer process or a serializing queue.

## Configuration

**Performance PRAGMAs (set per connection after open):**
```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = -64000;   -- 64 MB (negative = kibibytes)
PRAGMA temp_store = MEMORY;
PRAGMA mmap_size = 268435456; -- 256 MB memory-mapped I/O
PRAGMA busy_timeout = 5000;   -- ms to wait on locked database
```

**Development vs production:**
- Development: `synchronous = OFF` is acceptable for speed (data loss on OS crash, not app crash).
- Production: `synchronous = NORMAL` with WAL is the recommended balance. `synchronous = FULL` is only needed for financial-grade durability without a UPS.

**Connection string (Python):**
```python
conn = sqlite3.connect("app.db", timeout=5, check_same_thread=False)
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("PRAGMA foreign_keys=ON")
```

## Performance

**EXPLAIN QUERY PLAN to verify index usage:**
```sql
EXPLAIN QUERY PLAN
SELECT * FROM orders WHERE user_id = 42 ORDER BY created_at DESC LIMIT 10;
-- Look for: "USING INDEX" vs "SCAN TABLE" (full scan)
```

**Partial and expression indexes:**
```sql
-- Index only active rows
CREATE INDEX idx_active_users ON users (email) WHERE deleted_at IS NULL;
-- Expression index for case-insensitive lookup
CREATE INDEX idx_users_email_lower ON users (lower(email));
```

**Avoid `SELECT COUNT(*)` without WHERE on large tables** — SQLite has no statistics-based shortcut; it always scans. Maintain a separate counter in a settings table for large datasets.

**Checkpoint WAL periodically in long-running processes:**
```sql
PRAGMA wal_checkpoint(TRUNCATE);
```
Without checkpointing, the WAL file grows unbounded. In most apps the default auto-checkpoint (every 1000 pages) is sufficient.

**Avoid column type affinity mismatches:** SQLite uses dynamic typing but indexes are type-sensitive. Storing `"42"` (text) in a column queried as integer `42` will miss the index.

## Security

**Parameterized queries (no string concatenation):**
```go
rows, err := db.Query("SELECT * FROM users WHERE email = ?", email)
```
SQLite is just as vulnerable to SQL injection as any other database.

**Encryption at rest:** SQLite has no built-in encryption. Use SQLCipher (open-source AES-256 extension) for mobile apps storing sensitive data:
```kotlin
// Android (SQLCipher)
SQLiteDatabase.loadLibs(context)
val db = SQLiteDatabase.openOrCreateDatabase(dbFile, passphrase, null)
```

**File permissions:** Restrict the database file to the owning process user (`chmod 600`). On mobile, store in the app's private data directory — never on external storage.

**No network exposure:** SQLite has no network listener. Never serve it via a network proxy in production (no auth, no audit log, no connection limits).

## Testing

**Use in-memory databases for fast unit tests:**
```python
conn = sqlite3.connect(":memory:")
# Apply migrations, run tests — no filesystem I/O
```
Each test can get its own `:memory:` database for full isolation without teardown cost.

For integration tests that need file-based behavior (WAL, locking), use a temp-directory file:
```python
import tempfile, os
db_path = os.path.join(tempfile.mkdtemp(), "test.db")
```

Testcontainers is not needed for SQLite — the embedded nature is the point. Use the real library in tests rather than mocking it.

## Dos
- Always enable `PRAGMA journal_mode=WAL` and `PRAGMA foreign_keys=ON` immediately after opening a connection.
- Wrap bulk inserts in explicit transactions — it is the single largest performance lever.
- Use `PRAGMA busy_timeout` to handle concurrent access gracefully instead of catching `SQLITE_BUSY` exceptions.
- Store the schema version in `user_version` and apply migrations incrementally at startup.
- Use `:memory:` databases in unit tests for speed and isolation.
- Pin the SQLite version in your build (bundled SQLite in mobile frameworks is fine; avoid system SQLite which varies by OS).
- Use `WITHOUT ROWID` tables for tables with composite primary keys and no rowid-based access pattern — reduces storage for narrow tables.

## Don'ts
- Don't use SQLite for multi-process or multi-server write workloads — WAL helps concurrency within one process, not across processes or machines.
- Don't leave `PRAGMA foreign_keys` at its default (OFF) — you will accumulate orphaned rows silently.
- Don't store blobs larger than ~1 MB in SQLite — large blobs bloat the database file and slow page cache; store them on the filesystem and keep the path.
- Don't use SQLite as a message queue or job queue — the single-writer constraint causes head-of-line blocking under concurrent consumers.
- Don't use `synchronous=OFF` in production — a crash or power loss will corrupt the database.
- Don't assume type safety — SQLite's flexible typing means `INSERT INTO t(int_col) VALUES('hello')` succeeds silently; validate at the application layer.
- Don't share a single `sqlite3.Connection` across threads without `check_same_thread=False` and explicit locking — SQLite connections are not thread-safe by default.
