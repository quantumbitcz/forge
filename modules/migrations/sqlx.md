# SQLx Migrations Best Practices

## Overview
SQLx is an async Rust SQL toolkit with compile-time query verification. Its migration system uses plain SQL files and integrates with the macro-based query checking workflow. Use it for Rust async projects (Tokio/async-std) that need runtime flexibility without a full ORM. Avoid it when you need a schema builder DSL — SQLx migrations are always plain SQL.

## Architecture Patterns

### Directory structure
```
migrations/
├── 20240101120000_create_users.sql          # non-reversible
├── 20240101120000_create_users.up.sql       # reversible (up)
├── 20240101120000_create_users.down.sql     # reversible (down)
├── 20240115093000_add_email_index.up.sql
└── 20240115093000_add_email_index.down.sql
```

Use either the single-file format (non-reversible) or the `.up.sql`/`.down.sql` pair format — do not mix in the same project.

### Create a migration
```bash
# Non-reversible (single file)
sqlx migrate add create_users

# Reversible (paired .up.sql / .down.sql)
sqlx migrate add -r create_users
```

### up.sql / down.sql
```sql
-- migrations/20240101120000_create_users.up.sql
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL,
    name VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT users_email_unique UNIQUE (email)
);

-- migrations/20240101120000_create_users.down.sql
DROP TABLE IF EXISTS users;
```

### Apply migrations at runtime
```rust
use sqlx::PgPool;

pub async fn run_migrations(pool: &PgPool) -> anyhow::Result<()> {
    sqlx::migrate!("./migrations")
        .run(pool)
        .await
        .map_err(|e| anyhow::anyhow!("Migration failed: {}", e))?;
    Ok(())
}
```
Call this at application startup before the server begins accepting traffic.

### CLI workflow
```bash
sqlx migrate run      # apply pending migrations
sqlx migrate revert   # revert last reversible migration
sqlx migrate info     # list applied/pending migrations
```

## Configuration

### Cargo.toml
```toml
[dependencies]
sqlx = { version = "0.8", features = ["runtime-tokio", "postgres", "chrono", "uuid", "migrate"] }
```

### DATABASE_URL
```bash
# .env (development only)
DATABASE_URL=postgres://user:pass@localhost/myapp
```

### Offline mode (sqlx prepare)
Compile-time query checking requires a live database during `cargo build`. For CI without a DB, use offline mode:
```bash
# Generate .sqlx/ query metadata (run locally with a live DB)
cargo sqlx prepare

# In CI: use cached metadata
SQLX_OFFLINE=true cargo build
```
Commit `.sqlx/` to version control and regenerate it whenever queries change.

## Performance

### Zero-downtime: nullable then enforce
```sql
-- 20240201_add_display_name.up.sql (Deploy N)
ALTER TABLE users ADD COLUMN display_name VARCHAR(255);

-- 20240210_enforce_display_name.up.sql (Deploy N+1, after backfill)
UPDATE users SET display_name = name WHERE display_name IS NULL;
ALTER TABLE users ALTER COLUMN display_name SET NOT NULL;
```

```sql
-- 20240210_enforce_display_name.down.sql
ALTER TABLE users ALTER COLUMN display_name DROP NOT NULL;
```

### Large-table index without locking
```sql
-- up.sql
CREATE INDEX CONCURRENTLY idx_orders_created_at ON orders(created_at);

-- down.sql
DROP INDEX CONCURRENTLY IF EXISTS idx_orders_created_at;
```

### CI verification without a live DB
```bash
# Verify all migrations parse and are in order (no DB needed)
sqlx migrate info --source migrations
SQLX_OFFLINE=true cargo check
```

## Security
- Store `DATABASE_URL` in environment variables or a secrets manager; never commit credentials
- Use a dedicated migration user with DDL rights; the application pool user needs DML only
- Commit `.sqlx/` query metadata but never credentials
- `.env` must be in `.gitignore`

## Testing
```rust
#[sqlx::test(migrations = "./migrations")]
async fn test_user_creation(pool: PgPool) {
    // sqlx::test automatically runs migrations against a fresh test DB
    let user = sqlx::query_as!(User, "INSERT INTO users (email) VALUES ($1) RETURNING *", "a@b.com")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(user.email, "a@b.com");
}
```
The `#[sqlx::test]` macro creates an isolated database per test, runs all migrations, and tears down after the test. No manual setup needed.

```bash
# CI: verify migrations apply cleanly
DATABASE_URL=postgres://localhost/test_ci sqlx migrate run
cargo test
```

## Dos
- Use `#[sqlx::test]` for integration tests — it handles migration + isolation automatically
- Commit `.sqlx/` offline query data and regenerate with `cargo sqlx prepare` after query changes
- Always write `.down.sql` for reversible migrations and test revert in CI
- Use `sqlx migrate info` in a startup health check to detect pending migrations
- Keep migration SQL ANSI-compatible where possible; use dialect-specific features sparingly and comment them
- Pin the `sqlx` version to avoid incompatible migration table schema changes

## Don'ts
- Never modify a migration file after it has been applied — SQLx checksums every file
- Don't mix reversible and non-reversible migration files in the same project
- Avoid storing compile-time query metadata (`.sqlx/`) with credentials embedded
- Don't skip `DATABASE_URL` validation at startup — a missing or wrong URL causes cryptic compile errors in offline mode
- Never run migrations directly on production without first applying them to a staging environment with production data
- Avoid large unbounded `UPDATE` statements in migrations without batch processing on tables with millions of rows
