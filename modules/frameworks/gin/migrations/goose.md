# Gin + goose Migrations

> Gin-specific patterns for goose migrations. Extends `modules/migrations/goose.md`.
> Generic goose patterns are NOT repeated here.

## Integration Setup

```go
// go.mod
require github.com/pressly/goose/v3 v3.21.0
```

## Run at Startup Before Router Setup

```go
func main() {
    dsn := os.Getenv("DATABASE_URL")

    // 1. Open a database/sql connection for migrations
    sqlDB, err := sql.Open("pgx", dsn)
    if err != nil {
        log.Fatalf("open db for migrations: %v", err)
    }

    // 2. Run migrations — block startup until complete
    if err := db.RunMigrations(context.Background(), sqlDB); err != nil {
        log.Fatalf("migrations failed: %v", err)
    }
    sqlDB.Close() // migrations done; close this connection

    // 3. Open pgxpool for the application
    pool, err := db.NewPool(context.Background(), dsn)
    if err != nil {
        log.Fatalf("open pool: %v", err)
    }
    defer pool.Close()

    // 4. Set up Gin router
    r := setupRouter(pool)
    r.Run(":8080")
}
```

## Embedded Migrations

```go
// internal/db/migrations.go
package db

import "embed"

//go:embed migrations/*.sql
var MigrationsFS embed.FS
```

```go
// internal/db/migrate.go
func RunMigrations(ctx context.Context, db *sql.DB) error {
    goose.SetBaseFS(MigrationsFS)
    if err := goose.SetDialect("postgres"); err != nil {
        return err
    }
    return goose.UpContext(ctx, db, "migrations")
}
```

## Scaffolder Patterns

```yaml
patterns:
  migrations_dir: "internal/db/migrations/"
  embed_file: "internal/db/migrations.go"
  migrate_func: "internal/db/migrate.go"
  main_startup: "cmd/server/main.go"  # migration call goes here before router init
```

## Additional Dos/Don'ts

- DO run migrations synchronously before `gin.New()` is called — no HTTP traffic before schema is ready
- DO use a separate `database/sql` connection for migrations even when the app uses `pgxpool`
- DO embed migration files so the Docker image is a single self-contained artifact
- DON'T run migrations from a Gin handler or middleware — only at process startup
- DON'T share the migration `*sql.DB` with the application pool — close it after `goose.UpContext` returns
