# Go stdlib + PostgreSQL (database/sql + pgx)

> Go stdlib database patterns using `database/sql` with `pgx` driver.
> Generic Go conventions are NOT repeated here.

## Integration Setup

```go
// go.mod
require (
    github.com/jackc/pgx/v5 v5.7.0
    github.com/jackc/pgx/v5/pgxpool // bundled in pgx/v5
)
```

```go
import (
    "context"
    "database/sql"

    _ "github.com/jackc/pgx/v5/stdlib" // database/sql driver
    "github.com/jackc/pgx/v5/pgxpool"  // native pool API
)
```

## Connection Pool Setup

```go
// Prefer pgxpool for new code — richer config, native context cancellation
func NewPool(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
    cfg, err := pgxpool.ParseConfig(dsn)
    if err != nil {
        return nil, fmt.Errorf("parse config: %w", err)
    }
    cfg.MaxConns = 20
    cfg.MinConns = 2
    cfg.MaxConnLifetime = 30 * time.Minute
    cfg.MaxConnIdleTime = 5 * time.Minute
    cfg.ConnConfig.ConnectTimeout = 5 * time.Second

    pool, err := pgxpool.NewWithConfig(ctx, cfg)
    if err != nil {
        return nil, fmt.Errorf("create pool: %w", err)
    }
    return pool, nil
}
```

## Prepared Statements

```go
// Prepare once at startup and cache
type Queries struct {
    getUserByID *pgxpool.Pool // reuse pool; pgx prepares per-connection automatically
}

// For database/sql: prepare on pool (shared across connections)
stmt, err := db.PrepareContext(ctx, "SELECT id, name FROM users WHERE id = $1")
if err != nil {
    return fmt.Errorf("prepare: %w", err)
}
defer stmt.Close()

row := stmt.QueryRowContext(ctx, userID)
```

## Context Cancellation

```go
// All operations accept context — always pass the request context
func GetUser(ctx context.Context, pool *pgxpool.Pool, id uuid.UUID) (*User, error) {
    row := pool.QueryRow(ctx, `SELECT id, name, email FROM users WHERE id = $1`, id)
    var u User
    if err := row.Scan(&u.ID, &u.Name, &u.Email); err != nil {
        if errors.Is(err, pgx.ErrNoRows) {
            return nil, ErrNotFound
        }
        return nil, fmt.Errorf("scan user: %w", err)
    }
    return &u, nil
}
```

## Transactions

```go
func CreateUserWithAudit(ctx context.Context, pool *pgxpool.Pool, data CreateUserInput) (*User, error) {
    tx, err := pool.Begin(ctx)
    if err != nil {
        return nil, fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx) // no-op if committed

    var u User
    err = tx.QueryRow(ctx,
        `INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id, name, email`,
        data.Name, data.Email,
    ).Scan(&u.ID, &u.Name, &u.Email)
    if err != nil {
        return nil, fmt.Errorf("insert user: %w", err)
    }

    _, err = tx.Exec(ctx,
        `INSERT INTO audit_logs (action, user_id) VALUES ('USER_CREATED', $1)`, u.ID)
    if err != nil {
        return nil, fmt.Errorf("insert audit: %w", err)
    }

    return &u, tx.Commit(ctx)
}
```

## Scaffolder Patterns

```yaml
patterns:
  db_package: "internal/db/"
  pool_setup: "internal/db/postgres.go"
  repository: "internal/repository/{entity}_repository.go"
  model: "internal/model/{entity}.go"
  migrations_dir: "migrations/"
```

## Additional Dos/Don'ts

- DO use `pgxpool.Pool` directly for most services; fall back to `database/sql` only for library compatibility
- DO always defer `tx.Rollback(ctx)` immediately after `Begin` — it is safe to call after `Commit`
- DO check for `pgx.ErrNoRows` and surface it as a domain-level `ErrNotFound`
- DO set `ConnectTimeout` and `MaxConnLifetime` to bound unbounded waits and stale connections
- DON'T use `context.Background()` inside handlers — propagate the request context for cancellation
- DON'T scan into `*interface{}` — always use typed destination variables
- DON'T share a single `*sql.Stmt` across goroutines without `PrepareContext` on the pool (not a single conn)
