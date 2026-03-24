# Gin + PostgreSQL (pgx)

> Gin-specific patterns for PostgreSQL with pgx. Extends go-stdlib database patterns.
> Raw pgx pool setup is in `modules/frameworks/go-stdlib/databases/postgresql.md`.

## Integration Setup

```go
// go.mod
require (
    github.com/gin-gonic/gin v1.10.0
    github.com/jackc/pgx/v5 v5.7.0
)
```

## DB Pool as Gin Middleware

```go
func DBMiddleware(pool *pgxpool.Pool) gin.HandlerFunc {
    return func(c *gin.Context) {
        c.Set("db", pool)
        c.Next()
    }
}

// Wire at router setup
r := gin.New()
pool, _ := NewPool(context.Background(), os.Getenv("DATABASE_URL"))
r.Use(DBMiddleware(pool))
```

## Context Propagation in Handlers

```go
func GetUserHandler(c *gin.Context) {
    pool := c.MustGet("db").(*pgxpool.Pool)
    id, err := uuid.Parse(c.Param("id"))
    if err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
        return
    }

    // Pass gin's request context — honours client disconnects and timeouts
    user, err := getUserByID(c.Request.Context(), pool, id)
    if errors.Is(err, ErrNotFound) {
        c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
        return
    }
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
        return
    }
    c.JSON(http.StatusOK, user)
}
```

## Repository Injection via Closure (preferred over context keys)

```go
func NewUserHandler(repo UserRepository) gin.HandlerFunc {
    return func(c *gin.Context) {
        id, _ := uuid.Parse(c.Param("id"))
        user, err := repo.GetByID(c.Request.Context(), id)
        // ...
    }
}

// Router setup
userRepo := NewPgxUserRepository(pool)
r.GET("/users/:id", NewUserHandler(userRepo))
```

## Scaffolder Patterns

```yaml
patterns:
  db_middleware: "internal/middleware/db.go"
  pool_setup: "internal/db/postgres.go"
  repository: "internal/repository/{entity}_repository.go"
  handler: "internal/handler/{entity}_handler.go"
```

## Additional Dos/Don'ts

- DO prefer closure injection over `c.MustGet("db")` — closures are type-safe and testable
- DO use `c.Request.Context()` (not `context.Background()`) so database queries respect HTTP deadlines
- DO close the pool via `pool.Close()` in the graceful shutdown handler
- DON'T call `pool.QueryRow` directly in handler functions — route through a repository interface
- DON'T share a `pgxpool.Conn` across handler calls — acquire and release per operation
