# Go stdlib + goose

> Go stdlib patterns for goose database migrations. Extends generic goose conventions.
> See `modules/migrations/goose.md` for tool-level best practices.

## Integration Setup

```go
// go.mod
require (
    github.com/pressly/goose/v3 v3.21.0
)
```

## Embed Migrations in Binary

```go
// internal/db/migrations.go
package db

import "embed"

//go:embed migrations/*.sql
var MigrationsFS embed.FS
```

## Run Migrations at Startup

```go
// internal/db/migrate.go
package db

import (
    "context"
    "database/sql"
    "fmt"

    "github.com/pressly/goose/v3"
)

func RunMigrations(ctx context.Context, db *sql.DB) error {
    goose.SetBaseFS(MigrationsFS)
    if err := goose.SetDialect("postgres"); err != nil {
        return fmt.Errorf("goose dialect: %w", err)
    }
    if err := goose.UpContext(ctx, db, "migrations"); err != nil {
        return fmt.Errorf("goose up: %w", err)
    }
    return nil
}
```

Call `RunMigrations` before the HTTP server starts and before the pgxpool is opened for application traffic.

## Create a Migration

```bash
goose -dir migrations create add_users_table sql
# Creates: migrations/20240101120000_add_users_table.sql
```

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

## Go-Based Migration (when SQL is insufficient)

```go
// migrations/20240202120000_backfill_display_name.go
package migrations

import (
    "context"
    "database/sql"
    "github.com/pressly/goose/v3"
)

func init() {
    goose.AddMigrationContext(upBackfillDisplayName, downBackfillDisplayName)
}

func upBackfillDisplayName(ctx context.Context, tx *sql.Tx) error {
    _, err := tx.ExecContext(ctx,
        `UPDATE users SET display_name = name WHERE display_name IS NULL`)
    return err
}

func downBackfillDisplayName(ctx context.Context, tx *sql.Tx) error {
    _, err := tx.ExecContext(ctx, `UPDATE users SET display_name = NULL`)
    return err
}
```

## Scaffolder Patterns

```yaml
patterns:
  migrations_dir: "internal/db/migrations/"
  embed_file: "internal/db/migrations.go"
  migrate_func: "internal/db/migrate.go"
  migration_sql: "internal/db/migrations/{timestamp}_{name}.sql"
  migration_go: "internal/db/migrations/{timestamp}_{name}.go"
```

## Additional Dos/Don'ts

- DO embed migrations with `//go:embed` so the binary is a single deployable artifact
- DO use `UpContext` (not `Up`) to respect context cancellation during startup
- DO always write a correct `-- +goose Down` block — rollback capability is required
- DO pin the goose CLI version in CI to match the library version in `go.mod`
- DON'T run `goose reset` or `goose down-to 0` in production environments
- DON'T modify a migration file after it has been applied — goose tracks checksums
- DON'T open the application pgxpool before migrations complete — serve no traffic until schema is ready
