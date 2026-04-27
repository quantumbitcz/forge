# Gin Framework Conventions

> Support tier: contract-verified

> Framework-specific conventions for Go + Gin projects. Language idioms are in `modules/languages/go.md`. Generic testing patterns are in `modules/testing/go-testing.md`.

## Architecture (Handler / Service / Repository)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `handler/` | Gin handler functions, request binding, response writing | services (via interface) |
| `service/` | Business logic, validation, orchestration | repositories (via interface) |
| `repository/` | Database access, SQL queries, migrations | database driver |
| `model/` | Domain types, value objects, request/response DTOs | stdlib only |
| `middleware/` | Auth, logging, CORS, recovery, rate limiting | `gin.Context` |
| `router/` | Route registration, group setup, middleware wiring | handler, middleware |
| `cmd/` | Application entry points, dependency wiring | all packages |

**Dependency rule:** Handlers never import repository packages directly. Services mediate all data access. All cross-layer dependencies flow through interfaces defined at the consumer side.

## Routing and Route Groups

```go
r := gin.New()  // never gin.Default() — configure middleware explicitly

// Versioned API groups
v1 := r.Group("/api/v1")
{
    users := v1.Group("/users")
    users.Use(authMiddleware())
    {
        users.GET("", userHandler.List)
        users.GET("/:id", userHandler.GetByID)
        users.POST("", userHandler.Create)
        users.PUT("/:id", userHandler.Update)
        users.DELETE("/:id", userHandler.Delete)
    }
}
```

- Group routes by domain — one `RouterGroup` per resource area
- Version via URL path (`/api/v1/`), not query parameters or headers
- Attach middleware at the group level, not per-route, when it applies to the entire group
- Use `gin.New()` + explicit middleware; never `gin.Default()` which uses a global logger and panic recovery you cannot customize

## Middleware

```go
// Custom middleware signature
func AuthMiddleware(secret string) gin.HandlerFunc {
    return func(c *gin.Context) {
        token := c.GetHeader("Authorization")
        if !isValid(token, secret) {
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
            return
        }
        c.Set("userID", extractUserID(token))
        c.Next()
    }
}
```

- Middleware functions return `gin.HandlerFunc` — use closures to inject dependencies
- Call `c.Abort()` or `c.AbortWithStatus()` to stop the chain; never just `return` without aborting
- Call `c.Next()` explicitly when the middleware should continue the chain
- Attach recovery middleware first: it must wrap all other middleware
- Middleware order: recovery → logging → CORS → auth → rate-limiting → handler

## Request Handling

```go
type CreateUserRequest struct {
    Name  string `json:"name"  binding:"required,min=1,max=100"`
    Email string `json:"email" binding:"required,email"`
}

func (h *UserHandler) Create(c *gin.Context) {
    var req CreateUserRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }
    user, err := h.svc.Create(c.Request.Context(), req.Name, req.Email)
    if err != nil {
        h.handleError(c, err)
        return
    }
    c.JSON(http.StatusCreated, toUserResponse(user))
}
```

- Use `c.ShouldBindJSON()` — unlike `c.Bind()`, it does not abort on error
- Use `c.ShouldBindQuery()` for query params, `c.ShouldBindUri()` for path params
- Always define typed request structs with `binding:` tags
- Use `validator/v10` tags for validation; register custom validators at startup
- Never pass `c.Param()` or `c.Query()` raw values to business logic without validation
- Return typed response structs — never return domain models directly

## Error Handling

```go
// Custom error type
type AppError struct {
    Code    int
    Message string
    Err     error
}

// Centralized error middleware
func ErrorMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        c.Next()
        if len(c.Errors) > 0 {
            last := c.Errors.Last()
            var appErr *AppError
            if errors.As(last.Err, &appErr) {
                c.JSON(appErr.Code, gin.H{"error": appErr.Message})
                return
            }
            c.JSON(http.StatusInternalServerError, gin.H{"error": "internal server error"})
        }
    }
}
```

- Use `c.Error(err)` in handlers to attach errors; let centralized middleware respond
- Define custom error types with HTTP status codes — map domain errors to HTTP at the handler boundary
- Never use `panic` in handlers — use error returns
- Services never know about HTTP status codes — only handlers map errors to responses
- Log the original error (with stack/context); return a sanitized message to the client

## Dependency Injection

- No DI framework — wire dependencies in `main()` and pass via constructors
- Functional options for optional service config: `NewUserService(db, WithCache(c), WithMetrics(m))`
- Handlers receive service interfaces (not concrete implementations)
- Use `gin.Context.Set()` / `gin.Context.Get()` only for request-scoped values (e.g., authenticated user ID)
- Never use package-level variables for mutable state

## Database Patterns

> Specific driver and ORM patterns (`database/sql` + `pgx`, GORM, `sqlx`, etc.) are in the `persistence/` binding files. This section covers generic database conventions.

- Connection pooling: configure max open connections, max idle connections, and connection max lifetime explicitly
- Parameterized queries only — never string interpolation in SQL
- Use a migration tool appropriate to your `persistence:` choice (see persistence binding file)
- Always pass `context.Context` to database calls for cancellation/timeout propagation

## Security

- JWT validation in middleware before any protected handler
- Input validation at handler boundary via `binding:` tags and custom validators
- Parameterized queries — no raw string SQL concatenation
- CORS via `github.com/gin-contrib/cors` — configure `AllowOrigins` explicitly; never `*` in production
- Rate limiting via `github.com/gin-contrib/ratelimit` on auth and write endpoints
- HTTPS termination at load balancer; never accept sensitive data over plain HTTP
- Secrets from environment variables — never hardcode in source

## Performance

- Gin's zero-allocation router — avoid unnecessary middleware that copies request data
- Connection pooling for all database connections
- `context.WithTimeout()` for all database and external service calls
- Graceful shutdown: `http.Server.Shutdown(ctx)` with a 30-second timeout to drain connections
- Use `sync.Pool` for large objects (e.g., response buffers) created per request

## Naming

Follow Go conventions: short variable names in functions, unexported by default, no `I-` prefix on interfaces.

| Artifact | Pattern | Example |
|----------|---------|---------|
| Handler | `{Area}Handler` | `UserHandler` |
| Service interface | `{Area}Service` | `UserService` |
| Repository interface | `{Area}Repository` | `UserRepository` |
| Constructor | `New{Type}` | `NewUserHandler` |
| Middleware | `{Name}Middleware` | `AuthMiddleware` |
| Request DTO | `Create{Area}Request` | `CreateUserRequest` |
| Response DTO | `{Area}Response` | `UserResponse` |

## Logging

- Use `slog` (Go 1.21+) with JSON handler for production
- Request logging middleware: method, path, status, latency, request ID
- Log errors with full context before returning sanitized response
- Never log sensitive data: tokens, passwords, PII

## Testing

### Test Framework
- **Go standard `testing` package** — no external test framework needed
- **`httptest`** for HTTP handler and middleware integration tests
- **`testcontainers-go`** for database integration tests with real PostgreSQL
- **`gomock`** or hand-written fakes for mocking service interfaces

### Integration Test Patterns
- Use `httptest.NewRecorder()` + `gin.CreateTestContext()` for handler unit tests
- Use `httptest.NewServer(router)` for full integration tests through the middleware stack
- Test middleware behavior by constructing a test Gin engine with the middleware and a dummy handler
- Use table-driven tests for input/output variations across endpoint parameters

### What to Test
- Handler request/response contracts: status codes, JSON shapes, validation error messages
- Service-layer business logic with mocked repository interfaces
- Middleware behavior: auth rejection, CORS headers, rate limiting responses
- Request binding: verify `ShouldBindJSON` / `ShouldBindQuery` error handling
- Repository queries against a real database (via Testcontainers)

### What NOT to Test
- Gin returns 404 for unmatched routes or 405 for wrong HTTP methods — Gin handles this
- Gin middleware chain execution order — trust the framework
- `validator/v10` validates standard tags (e.g., `required`, `email`) correctly
- `encoding/json` marshals standard types

### Example Test Structure
```
internal/
  handler/
    user_handler.go
    user_handler_test.go         # httptest + gin.CreateTestContext
  service/
    user_service.go
    user_service_test.go         # unit tests with mocked repos
  middleware/
    auth_middleware_test.go      # middleware isolation tests
```

For general Go testing patterns, see `modules/testing/go-testing.md`.

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Smart Test Rules

- No duplicate tests — grep existing tests before generating
- Test behavior, not implementation
- Table-driven tests for input/output variations
- One assertion focus per test — multiple asserts OK if testing the same behavior

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated handlers, changing middleware contracts, restructuring router groups.

## Dos and Don'ts

### Do
- Use `gin.New()` with explicit middleware — configure recovery and logger intentionally
- Use `c.ShouldBindJSON()` over `c.BindJSON()` — it does not abort on error
- Use `c.ShouldBindJSON()` — gives control to return errors rather than aborting
- Define typed request and response structs for every endpoint
- Use interface-driven design — inject dependencies via constructors
- Use `c.Request.Context()` when calling services to propagate cancellation
- Return early on errors — check, handle, then proceed
- Use custom error types with HTTP status mappings
- Wire all dependencies in `main()` — no global state

### Don't
- Don't use `gin.Default()` — configure gin.New() with explicit middleware
- Don't use `c.Bind()` — it calls `c.AbortWithError` on failure, bypassing your error handler
- Don't use `gin.H{}` for complex, repeated response shapes — define typed response structs
- Don't use `panic` in handlers — return errors
- Don't store mutable state in package-level variables — use dependency injection
- Don't access `c.Param()` or `c.Query()` values without validation
- Don't put business logic in handlers — handlers validate, delegate, and format only
- Don't ignore returned errors from `c.JSON()` in tests
- Don't use global `gin.SetMode()` — set mode per engine instance or via `GIN_MODE` env var
- Don't use `c.Next()` after calling `c.Abort()` — abort ends the chain
