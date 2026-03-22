# Go/Stdlib Agent Conventions Reference

> Full details in project CLAUDE.md. This is a curated subset for agent consumption.

## Architecture (Handler / Service / Repository)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `handler/` | HTTP handlers, request parsing, response writing | services (via interface) |
| `service/` | Business logic, orchestration, validation | repositories (via interface) |
| `repository/` | Data access, SQL queries | database driver |
| `model/` | Domain types, value objects | stdlib only |
| `middleware/` | Cross-cutting concerns: auth, logging, CORS | stdlib / chi / echo |
| `cmd/` | Application entry points, wire-up | all packages |

**Dependency rule:** Handlers never import repository packages directly. Services mediate all data access. All cross-layer dependencies flow through interfaces.

## Interface-Driven Design

- Define interfaces at the consumer side, not the provider side
- Keep interfaces small — prefer single-method interfaces
- Accept interfaces, return concrete types
- Mock generation via `go generate` with `mockgen` or hand-written fakes

```go
// In service package — defines what it needs from persistence
type UserRepository interface {
    FindByID(ctx context.Context, id uuid.UUID) (*model.User, error)
    Save(ctx context.Context, user *model.User) error
}
```

## Context Propagation

- Every exported function that performs I/O must accept `context.Context` as its first parameter
- Never store `context.Context` in a struct
- Use `context.WithTimeout` / `context.WithCancel` for deadline management
- Pass request-scoped values (trace ID, user ID) via context, not globals

## Error Handling

- Always check errors — never discard with `_`
- Wrap errors with context using `fmt.Errorf("operation: %w", err)`
- Error strings start with lowercase, no punctuation at end
- Use sentinel errors (`var ErrNotFound = errors.New("not found")`) for expected conditions
- Use custom error types for errors that carry additional data

```go
if err != nil {
    return fmt.Errorf("fetching user %s: %w", id, err)
}
```

| Error Type | HTTP Status |
|-----------|-------------|
| `ErrNotFound` | 404 |
| `ErrValidation` | 400 |
| `ErrForbidden` | 403 |
| `ErrConflict` | 409 |
| Unhandled | 500 |

## Package Structure

```
cmd/
  server/
    main.go             # Entry point, dependency wiring
internal/
  handler/              # HTTP handlers
    {area}_handler.go
  service/              # Business logic
    {area}_service.go
  repository/           # Data access
    {area}_repository.go
  model/                # Domain types
    {area}.go
  middleware/            # HTTP middleware
    auth.go
    logging.go
  config/               # Configuration loading
    config.go
pkg/                    # Shared utilities (if any)
migrations/             # SQL migration files
```

## Naming Patterns

| Artifact | Pattern | Example |
|----------|---------|---------|
| Handler | `{Area}Handler` | `UserHandler` |
| Service | `{Area}Service` | `UserService` |
| Repository | `{Area}Repository` | `UserRepository` |
| Model | `{Area}` (singular) | `User` |
| Constructor | `New{Type}` | `NewUserService` |
| Interface | `{Area}{Role}` | `UserRepository` (at consumer) |
| Test file | `{file}_test.go` | `user_service_test.go` |

## No Global State

- No package-level `var` for mutable state (DB connections, configs)
- Wire dependencies in `main()` and pass via constructors
- Use `sync.Once` only when truly needed (e.g., one-time init)

## Router Patterns (Gin / Echo / Chi / stdlib)

- Group routes by domain area
- Use middleware for auth, logging, recovery, CORS
- Extract path params and query params in handlers, validate early
- Return structured JSON errors consistently

```go
mux := http.NewServeMux()
mux.Handle("GET /users/{id}", userHandler.GetByID())
mux.Handle("POST /users", userHandler.Create())
```

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels
- GoDoc comments on all exported types and functions
- No `panic()` in library/application code — only in `main()` or test helpers
- `gofmt` / `goimports` enforced — no manual formatting
- Lint with `staticcheck` or `golangci-lint`
- Max line length: soft 120

## Testing

- **Framework:** stdlib `testing` package + `testify/assert` for assertions
- **Table-driven tests:** Use `[]struct{ name string; ... }` with `t.Run(name, ...)`
- **HTTP tests:** `httptest.NewServer` / `httptest.NewRecorder` for handler tests
- **Database tests:** testcontainers-go or dockertest for integration tests
- **Mocks:** `mockgen` or hand-written fakes implementing interfaces
- **Rules:** Test behavior not implementation, one assertion focus per subtest, use table-driven tests for variants

```go
func TestUserService_Create(t *testing.T) {
    tests := []struct {
        name    string
        input   model.CreateUserRequest
        wantErr bool
    }{
        {"valid user", model.CreateUserRequest{Name: "Alice"}, false},
        {"empty name", model.CreateUserRequest{Name: ""}, true},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // ...
        })
    }
}
```

## Security

- Validate and sanitize all input at handler boundary
- Use parameterized queries — never string interpolation for SQL
- JWT validation via middleware
- CORS configured restrictively for production
- Secrets from environment variables, never hardcoded

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated files, changing APIs, fixing pre-existing bugs.

## Dos and Don'ts

### Do
- Return errors as the last return value — always check errors immediately
- Use `context.Context` as first parameter for functions that do I/O or may block
- Use `errors.Is()` and `errors.As()` for error comparison (not `==`)
- Use `defer` for cleanup — files, locks, connections
- Use `sync.Mutex` for shared mutable state — or prefer channels for communication
- Use table-driven tests for input/output variations

### Don't
- Don't ignore errors with `_` — at minimum log them
- Don't use `panic` for expected errors — only for programmer bugs (invariant violations)
- Don't use global variables for state — use dependency injection via struct methods
- Don't use `init()` for complex initialization — prefer explicit setup functions
- Don't use `interface{}` (now `any`) without type assertion — narrow types as early as possible
- Don't use goroutines without ensuring they terminate — always pass a `context.Context` for cancellation

## Concurrency Safety

### Goroutine Management
- Always pass `context.Context` to goroutines for cancellation
- Use `errgroup.Group` for parallel tasks that share error state
- Use `sync.WaitGroup` only when you don't need error propagation
- Detect goroutine leaks in tests with `goleak` (uber-go/goleak)

### Common Data Races
- Never read and write a map concurrently — use `sync.Map` or protect with `sync.RWMutex`
- Slice append is not thread-safe — protect with mutex or use channels
- Use `-race` flag in tests to detect data races: `go test -race ./...`

## Performance Patterns

- Profile with `pprof` before optimizing — don't guess
- Use `sync.Pool` for frequently allocated/freed objects (buffers, structs)
- Prefer `strings.Builder` over `+` concatenation in loops
- Use buffered channels when producer/consumer speeds differ
- Benchmark with `testing.B`: `go test -bench=. -benchmem`
