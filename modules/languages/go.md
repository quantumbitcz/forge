# Go Language Conventions

## Type System

- Go uses structural typing via interfaces — a type satisfies an interface by implementing its methods, no explicit declaration required.
- Define interfaces at the consumer side (the package that uses them), not at the provider side. This avoids circular imports and keeps abstractions small.
- Keep interfaces small — prefer single-method interfaces (`io.Reader`, `io.Writer` pattern). Large interfaces are hard to mock and tightly couple packages.
- **Accept interfaces, return concrete types** — callers get flexibility; implementations stay simple.
- Use `struct` embedding for code reuse, not inheritance.
- Use `type MyId uuid.UUID` (newtypes) to add type safety to primitive identifiers.

## Null Safety / Error Handling

- Go has no exceptions — errors are values returned as the last return value.
- Always check errors immediately after the call: `if err != nil { return fmt.Errorf("context: %w", err) }`.
- Never discard errors with `_` — at minimum log them. Silent discards hide bugs.
- Wrap errors with context using `fmt.Errorf("operation: %w", err)` — preserves the error chain for `errors.Is()` / `errors.As()`.
- Use sentinel errors (`var ErrNotFound = errors.New("not found")`) for expected, checkable conditions.
- Use custom error types (structs implementing `error`) when errors need to carry additional structured data.
- Error strings start with lowercase and have no punctuation at the end (Go style convention).
- Use `errors.Is(err, ErrFoo)` and `errors.As(err, &target)` for comparison — not `==` (breaks with wrapping).

## Concurrency

- Every exported function that performs I/O or may block must accept `context.Context` as its first parameter.
- Never store `context.Context` in a struct field — pass it through function calls.
- Use `context.WithTimeout` / `context.WithCancel` for deadline management and cancellation.
- Pass request-scoped values (trace ID, user ID) via context — not package-level globals.
- Use goroutines with explicit cancellation: always pass a `context.Context` so goroutines can terminate.
- Use `errgroup.Group` for parallel tasks that share error state and need coordinated cancellation.
- Use `sync.WaitGroup` when you need to wait for goroutines but don't need error propagation.
- Protect shared mutable state with `sync.Mutex` or `sync.RWMutex`. Never read and write a map concurrently — use `sync.Map` or a mutex.
- Use channels for communication between goroutines; use mutexes for protecting shared state. Prefer channels when in doubt.
- Use `-race` flag in tests (`go test -race ./...`) to detect data races.

## Naming Idioms

- Packages: short, lowercase, no underscores, no mixed case (e.g., `user`, `httputil`).
- Exported names: `PascalCase`. Unexported: `camelCase`.
- Constructors: `New{Type}` (e.g., `NewUserService`).
- Interface names: often end in `-er` for single-method interfaces (`Reader`, `Writer`, `Handler`, `Stringer`).
- Acronyms: all-caps (`URL`, `HTTP`, `ID`) — not `Url`, `Http`, `Id`.
- Test files: `{file}_test.go`, co-located with the package under test.
- Avoid stuttering: if the package is `user`, the exported type is `Service` (not `UserService` — callers write `user.Service`).

## Idiomatic Patterns

- `defer` for cleanup: file close, mutex unlock, connection release — runs on function exit regardless of return path.
- `init()` is for simple setup only (registering flags, setting package defaults) — never for complex initialization or side effects with external dependencies.
- No package-level mutable `var` for runtime state (DB connections, caches) — wire via constructors in `main()`.
- Use `sync.Once` only for genuine one-time initialization, not as a lazy-loading shortcut.
- `gofmt` and `goimports` are non-negotiable — no manual formatting discussions.

## Anti-Patterns

- **Ignoring errors:** `result, _ := fn()` hides failures. Check all errors.
- **Panic for expected errors:** `panic` is for programmer bugs (invariant violations), not user errors or I/O failures. Return an error.
- **`interface{}` / `any` without immediate type assertion:** Loses type safety. Narrow types as early as possible.
- **Global mutable state:** Package-level vars for runtime data create initialization order problems and test isolation issues. Use dependency injection.
- **`init()` for complex initialization:** Runs automatically on import, making behavior implicit and hard to test. Use explicit setup functions.
- **Goroutine leaks:** Goroutines without a termination condition or context cancellation run forever. Always ensure goroutines can exit.
- **String concatenation in loops:** Use `strings.Builder` — `+` in a loop is O(n²).
- **Unused imports:** Go compilation fails on unused imports — this is enforced, not a convention.

## Dos
- Return errors as the last return value — Go's error handling convention: `result, err := fn()`.
- Use `context.Context` as the first parameter for functions that do I/O or need cancellation.
- Use `defer` for cleanup — file handles, mutexes, response bodies.
- Use `errgroup.Group` for managing concurrent goroutine lifecycles with error propagation.
- Use `go vet`, `staticcheck`, and `golangci-lint` in CI — they catch bugs the compiler misses.
- Use `table-driven tests` for comprehensive test coverage with minimal code duplication.
- Use `io.Reader`/`io.Writer` interfaces for composable I/O — avoid concrete types in function signatures.

## Don'ts
- Don't ignore errors (`result, _ := fn()`) — always check and handle or propagate them.
- Don't use `panic` for expected errors — it's for programmer bugs only; return `error` instead.
- Don't use `interface{}` / `any` without immediate type assertion — it loses type safety.
- Don't use `init()` for complex initialization — it runs implicitly on import and is hard to test.
- Don't leak goroutines — every goroutine must have a termination condition or context cancellation.
- Don't use package-level mutable `var` for runtime state — pass dependencies through constructors.
- Don't use `string` concatenation in loops — use `strings.Builder` (O(n) vs O(n²)).
