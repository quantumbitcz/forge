# Go Stdlib Framework Conventions

> Framework-specific conventions for Go stdlib projects. Language idioms are in `modules/languages/go.md`. Generic testing patterns are in `modules/testing/go-testing.md`.

## Architecture (Handler / Service / Repository)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `handler/` | HTTP handlers, request parsing, response writing | services (via interface) |
| `service/` | Business logic, orchestration, validation | repositories (via interface) |
| `repository/` | Data access, SQL queries | database driver |
| `model/` | Domain types, value objects | stdlib only |
| `middleware/` | Cross-cutting concerns: auth, logging, CORS | stdlib |
| `cmd/` | Application entry points, wire-up | all packages |

**Dependency rule:** Handlers never import repository packages directly. Services mediate all data access. All cross-layer dependencies flow through interfaces.

## Interface-Driven Design

- Define interfaces at the consumer side, not the provider side
- Keep interfaces small -- prefer single-method interfaces
- Accept interfaces, return concrete types
- Mock generation via `go generate` with `mockgen` or hand-written fakes

## Context Propagation

- Every exported function that performs I/O must accept `context.Context` as first parameter
- Never store `context.Context` in a struct
- Use `context.WithTimeout` / `context.WithCancel` for deadline management
- Pass request-scoped values (trace ID, user ID) via context

## Error Handling

- Always check errors -- never discard with `_`
- Wrap errors with context: `fmt.Errorf("operation: %w", err)`
- Error strings start with lowercase, no trailing punctuation
- Use sentinel errors for expected conditions
- Use custom error types for errors carrying additional data

| Error Type | HTTP Status |
|-----------|-------------|
| `ErrNotFound` | 404 |
| `ErrValidation` | 400 |
| `ErrForbidden` | 403 |
| `ErrConflict` | 409 |
| Unhandled | 500 |

## Router Patterns

- Use `http.NewServeMux()` (Go 1.22+ enhanced routing) or chi/echo/gin
- Group routes by domain area
- Use middleware for auth, logging, recovery, CORS
- Return structured JSON errors consistently

```go
mux := http.NewServeMux()
mux.Handle("GET /users/{id}", userHandler.GetByID())
mux.Handle("POST /users", userHandler.Create())
```

## Package Structure

```
cmd/server/main.go          # Entry point, dependency wiring
internal/
  handler/                   # HTTP handlers
  service/                   # Business logic
  repository/                # Data access
  model/                     # Domain types
  middleware/                 # HTTP middleware
  config/                    # Configuration loading
pkg/                         # Shared utilities (if any)
migrations/                  # SQL migration files
```

## Naming Patterns

| Artifact | Pattern | Example |
|----------|---------|---------|
| Handler | `{Area}Handler` | `UserHandler` |
| Service | `{Area}Service` | `UserService` |
| Repository | `{Area}Repository` | `UserRepository` |
| Constructor | `New{Type}` | `NewUserService` |
| Test file | `{file}_test.go` | `user_service_test.go` |

## No Global State

- No package-level `var` for mutable state
- Wire dependencies in `main()` and pass via constructors
- Use `sync.Once` only when truly needed

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels
- GoDoc comments on all exported types and functions
- No `panic()` in library/application code -- only in `main()` or test helpers
- `gofmt` / `goimports` enforced
- Lint with `staticcheck` or `golangci-lint`

## Concurrency Safety

### Goroutine Management
- Always pass `context.Context` for cancellation
- Use `errgroup.Group` for parallel tasks sharing error state
- Use `sync.WaitGroup` only when no error propagation needed
- Detect goroutine leaks with `goleak`

### Data Race Prevention
- Never read/write a map concurrently -- use `sync.Map` or `sync.RWMutex`
- Slice append is not thread-safe -- protect with mutex or use channels
- Use `-race` flag in tests

## Security

- Validate and sanitize all input at handler boundary
- Parameterized queries -- never string interpolation for SQL
- JWT validation via middleware
- CORS configured restrictively for production
- Secrets from environment variables

## Performance

- Profile with `pprof` before optimizing
- Use `sync.Pool` for frequently allocated/freed objects
- Prefer `strings.Builder` over `+` in loops
- Benchmark with `testing.B`: `go test -bench=. -benchmem`

## Testing

### Test Framework
- **Go standard `testing` package** — no external test framework needed
- **`httptest`** for HTTP handler and middleware integration tests
- **`testcontainers-go`** for database integration tests with real PostgreSQL/MySQL
- **`gomock`** or hand-written fakes for mocking service interfaces

### Integration Test Patterns
- Use `httptest.NewServer(handler)` or `httptest.NewRecorder()` for handler integration tests
- Test middleware by composing it with a test handler and verifying request/response transformation
- Use table-driven tests (`[]struct{ name string; ... }`) for input/output variations
- Use `testcontainers-go` for repository tests against a real database — avoid in-memory stubs for SQL logic
- Test context propagation: pass `context.WithTimeout` and verify cancellation is respected

### What to Test
- Handler request/response contracts: status codes, JSON response shapes, error responses
- Service-layer business logic with mocked repository interfaces
- Repository queries against a real database (via Testcontainers)
- Error wrapping: verify `errors.Is()` and `errors.As()` work through the error chain
- Goroutine safety: run tests with `-race` flag

### What NOT to Test
- `net/http` parses headers, query params, or request bodies — the stdlib does this
- `http.ServeMux` routes to the correct handler (Go 1.22+ enhanced routing is well-tested)
- `encoding/json` marshals standard types correctly
- `context.WithTimeout` cancels after the timeout — the stdlib guarantees this

### Example Test Structure
```
internal/
  handler/
    user_handler.go
    user_handler_test.go         # httptest integration tests
  service/
    user_service.go
    user_service_test.go         # unit tests with mocked repos
  repository/
    user_repository.go
    user_repository_test.go      # Testcontainers DB tests
```

For general Go testing patterns, see `modules/testing/go-testing.md`.

## Smart Test Rules

- No duplicate tests — grep existing tests before writing new ones
- Test business behavior, not implementation details
- Do NOT test framework guarantees (e.g., `net/http` parses headers, `json.Marshal` handles standard types)
- Do NOT test stdlib context mechanics or `http.ServeMux` routing resolution
- Each test scenario covers a unique code path
- Fewer meaningful tests > high coverage of trivial code

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated packages, changing exported function signatures, restructuring internal modules.

## Dos and Don'ts

### Do
- Return errors as last return value -- check immediately
- Use `context.Context` as first parameter for I/O functions
- Use `errors.Is()` and `errors.As()` for error comparison
- Use `defer` for cleanup -- files, locks, connections
- Use table-driven tests for input/output variations

### Don't
- Don't ignore errors with `_` -- at minimum log them
- Don't use `panic` for expected errors
- Don't use global variables for state -- use dependency injection
- Don't use `init()` for complex initialization
- Don't use goroutines without cancellation context
