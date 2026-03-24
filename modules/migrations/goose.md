# goose Best Practices

## Overview
goose is a Go database migration tool that supports both SQL and Go-based migrations. Use it for Go projects that need versioned schema evolution with optional embedded migration support. Prefer goose when: the project is written in Go, migrations need to embed into the binary, or Go-based data transformations are required. Prefer Flyway or Liquibase for JVM projects.

## Architecture Patterns

### Directory structure
```
internal/db/
├── migrations.go              # //go:embed FS declaration
├── migrate.go                 # RunMigrations() function called at startup
└── migrations/
    ├── 20240101120000_create_users.sql
    ├── 20240202120000_add_order_status.sql
    └── 20240303120000_backfill_display_name.go
```

### SQL migration anatomy
```sql
-- +goose Up
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- +goose Down
DROP TABLE users;
```

### Go-based migration (for data transformations)
```go
// internal/db/migrations/20240303120000_backfill_display_name.go
package migrations

import (
    "context"
    "database/sql"
    "github.com/pressly/goose/v3"
)

func init() {
    goose.AddMigrationContext(up, down)
}

func up(ctx context.Context, tx *sql.Tx) error {
    _, err := tx.ExecContext(ctx,
        `UPDATE users SET display_name = name WHERE display_name IS NULL`)
    return err
}

func down(ctx context.Context, tx *sql.Tx) error {
    _, err := tx.ExecContext(ctx, `UPDATE users SET display_name = NULL`)
    return err
}
```

## Configuration

### Embed migrations in binary
```go
// internal/db/migrations.go
package db

import "embed"

//go:embed migrations/*.sql migrations/*.go
var MigrationsFS embed.FS
```

```go
// internal/db/migrate.go
func RunMigrations(ctx context.Context, db *sql.DB) error {
    goose.SetBaseFS(MigrationsFS)
    if err := goose.SetDialect("postgres"); err != nil {
        return fmt.Errorf("set dialect: %w", err)
    }
    return goose.UpContext(ctx, db, "migrations")
}
```

### CLI usage
```bash
# Install
go install github.com/pressly/goose/v3/cmd/goose@latest

# Create a new migration
goose -dir internal/db/migrations create add_index_users_email sql

# Run pending
goose -dir internal/db/migrations postgres "$DATABASE_URL" up

# Check status
goose -dir internal/db/migrations postgres "$DATABASE_URL" status
```

## Performance

### Zero-downtime migrations
Split breaking schema changes across two deployments:

1. **Deploy N:** Add new nullable column (non-breaking)
2. **Deploy N+1:** Backfill data via Go migration, add NOT NULL, drop old column

```sql
-- +goose Up
ALTER TABLE users ADD COLUMN display_name TEXT;
-- +goose Down
ALTER TABLE users DROP COLUMN display_name;
```

### Large table indexes (Postgres)
```sql
-- +goose Up
-- +goose StatementBegin
CREATE INDEX CONCURRENTLY idx_users_email ON users(email);
-- +goose StatementEnd

-- +goose Down
DROP INDEX CONCURRENTLY IF EXISTS idx_users_email;
```

Use `-- +goose StatementBegin` / `-- +goose StatementEnd` blocks for multi-statement DDL or `CONCURRENTLY` operations.

## Security

- Never embed credentials in the migration DSN — inject via environment variables
- Use a dedicated migration database user with `CREATE`, `DROP`, `ALTER` privileges; the application runtime user needs only DML (`SELECT`, `INSERT`, `UPDATE`, `DELETE`)
- Store migration files in version control and treat them as immutable once merged
- Never run `goose reset` or `goose down-to 0` in production

## Testing

```bash
# Apply all migrations against a test database in CI
docker run -d --name test-pg -e POSTGRES_PASSWORD=test -p 5432:5432 postgres:16
export DATABASE_URL="postgres://postgres:test@localhost/postgres?sslmode=disable"
goose -dir internal/db/migrations postgres "$DATABASE_URL" up
# Run integration tests
goose -dir internal/db/migrations postgres "$DATABASE_URL" down  # verify rollback
```

Use Testcontainers in integration tests to spin up a fresh database and call `RunMigrations` before assertions.

## Dos

- DO embed migrations with `//go:embed` so the binary is a single self-contained deployment artifact
- DO always write a correct `-- +goose Down` block — rollback capability is required
- DO use `UpContext` (not `Up`) to respect context cancellation during startup
- DO run migrations synchronously before the application starts serving HTTP traffic
- DO keep migration filenames timestamped and descriptive: `YYYYMMDDHHMMSS_description.sql`
- DO pin the `goose/v3` CLI version in CI to match the library version in `go.mod`

## Don'ts

- DON'T modify a migration file after it has been applied — goose detects checksum changes
- DON'T run `goose reset` or `goose down-to 0` in production environments
- DON'T use `CONCURRENTLY` DDL inside a transaction — goose wraps each migration in a transaction by default; use `-- +goose NO TRANSACTION` annotation when needed
- DON'T apply migrations from a goroutine or HTTP handler — startup only
- DON'T share the migration `*sql.DB` with the application connection pool
