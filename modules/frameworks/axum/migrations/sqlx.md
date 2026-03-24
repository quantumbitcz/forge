# Axum + SQLx Migrations

> Axum-specific patterns for SQLx migrations. Extends generic Axum conventions.
> SQLx pool setup is covered in `persistence/sqlx.md`. Not repeated here.

## Integration Setup

```bash
cargo install sqlx-cli --no-default-features --features rustls,postgres
export DATABASE_URL="postgresql://user:pass@localhost/myapp"
sqlx database create
sqlx migrate add create_users
```

## Migration File Format

SQLx uses plain SQL files with an optional `-- reversible` section:

```sql
-- migrations/20240315120000_create_users.sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Reversible (undo) migrations use the separator `-- migrate:down`:

```sql
-- migrations/20240315120001_add_users_index.sql
CREATE INDEX CONCURRENTLY idx_users_email ON users(email);

-- migrate:down
DROP INDEX IF EXISTS idx_users_email;
```

## sqlx::migrate! Macro

Embeds migration SQL files into the binary at compile time:

```rust
// src/main.rs
sqlx::migrate!("./migrations")
    .run(&pool)
    .await
    .expect("Failed to run database migrations");
```

The path is relative to the workspace root (where `Cargo.toml` lives).

## SQLX_OFFLINE Mode

For CI environments without a live database, generate an offline query cache:

```bash
cargo sqlx prepare --database-url "$DATABASE_URL"
# Generates .sqlx/ directory — commit to version control
```

```yaml
# CI — no database needed
- name: Build
  run: cargo build
  env:
    SQLX_OFFLINE: true
```

## CLI Migration Commands

```bash
# Apply all pending migrations
sqlx migrate run

# Revert the most recent migration
sqlx migrate revert

# Show migration status
sqlx migrate info

# Force a specific version (use with caution)
sqlx migrate run --target-version 20240315120000
```

CI integration:
```yaml
- name: Run migrations
  run: sqlx migrate run
  env:
    DATABASE_URL: ${{ secrets.DATABASE_URL }}

- name: Verify sqlx prepare is up to date
  run: cargo sqlx prepare --check
  env:
    DATABASE_URL: ${{ secrets.DATABASE_URL }}
```

## Scaffolder Patterns

```yaml
patterns:
  migrations_dir: "migrations/"
  migration: "migrations/{timestamp}_{description}.sql"
  sqlx_cache: ".sqlx/"
```

## Additional Dos/Don'ts

- DO commit `.sqlx/` query cache to enable offline compilation in CI
- DO run `cargo sqlx prepare --check` in CI to detect schema drift
- DO name migrations with timestamps so ordering is explicit
- DON'T use `migrate!("./migrations")` path with trailing slash — macro is sensitive to path format
- DON'T write destructive migrations without testing the `-- migrate:down` path locally
- DON'T use `sqlx migrate revert` in production without a documented rollback plan
