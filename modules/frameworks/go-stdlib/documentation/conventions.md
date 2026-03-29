# Go (stdlib) Documentation Conventions

> Extends `modules/documentation/conventions.md` with Go-specific patterns.

## Code Documentation

- Use godoc format: a comment block immediately preceding the declaration, starting with the entity name.
- Package-level doc (`doc.go` or top of main file): describe the package's purpose, primary types, and typical usage pattern.
- Every exported function, type, method, and constant must have a godoc comment.
- Interface documentation: describe the contract, not the implementation. Document preconditions, postconditions, and error conditions.
- Error variables (`var ErrFoo = errors.New(...)`): document when the error is returned and what the caller should do.

```go
// Package user provides user account management operations.
//
// Use [Service] to create, update, and retrieve user accounts.
// All mutating operations require a valid [context.Context] for cancellation.
package user

// Service manages user accounts. The zero value is not valid;
// use [NewService] to construct an instance.
type Service struct { ... }

// Create creates a new user account with the given email and name.
// Returns [ErrEmailTaken] if email is already registered.
// The returned User is in a valid, persisted state.
func (s *Service) Create(ctx context.Context, cmd CreateCommand) (User, error) { ... }

// ErrEmailTaken is returned by [Service.Create] when the requested email
// is already associated with an existing account.
var ErrEmailTaken = errors.New("user: email already registered")
```

## Architecture Documentation

- Document package boundaries: what each package owns, what it imports, and what it must NOT import (to avoid cycles).
- Document interface types that cross package boundaries — they are the seams of the architecture.
- HTTP handlers: document route registration and handler responsibilities if using `net/http` directly. Use `openapi.yaml` for API contracts.
- Document goroutine ownership: which function starts the goroutine, what signal stops it, and who owns the channel.

## Diagram Guidance

- **Package dependency graph:** Mermaid class diagram showing packages and their import relationships.
- **Goroutine lifecycle:** Sequence or state diagram for long-lived goroutines and their shutdown paths.

## Dos

- `doc.go` for every non-trivial package — it is the entry point for `go doc`
- Document `error` sentinel values exhaustively — Go callers rely on `errors.Is` pattern
- Document context cancellation behavior for long-running operations

## Don'ts

- Don't godoc unexported symbols unless they are surprisingly non-obvious
- Don't write godoc that repeats the function signature — add semantic information
- Don't omit package docs — `go doc ./...` output is the browsable API reference
