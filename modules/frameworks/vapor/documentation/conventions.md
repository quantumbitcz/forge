# Vapor Documentation Conventions

> Support tier: community

> Extends `modules/documentation/conventions.md` with Vapor-specific patterns.

## Code Documentation

- Use Swift DocC (`///`) for all route controllers, middleware, and service protocols.
- Route controllers: document each handler function with its HTTP method, path, expected request body, and possible response codes.
- `Content` models: document fields, validation constraints, and the direction (request vs response vs both).
- `AsyncMiddleware` implementations: document what the middleware checks, what it injects into `Request`, and failure behavior.
- Fluent models: document relationships and any soft-delete / timestamps behavior.

```swift
/// Handles user account creation.
///
/// `POST /api/v1/users`
///
/// - Body: ``CreateUserRequest`` (JSON)
/// - Returns: ``UserResponse`` with `201 Created`
/// - Throws: `409 Conflict` if email is already registered
func create(_ req: Request) async throws -> Response { ... }
```

## Architecture Documentation

- Document the `configure.swift` setup: middleware stack order, database configuration, and queue workers.
- Document the `routes.swift` route table — a summary table of all routes, methods, and auth requirements.
- Document Fluent migration history: list migrations in order and what schema change each performs.
- Leaf templates (if used): document template variables and which controller passes them.

## Diagram Guidance

- **Middleware pipeline:** Sequence diagram showing request processing through registered middleware.
- **Route table:** Tabular doc (not a diagram) listing route, method, auth requirement, and handler.

## Dos

- Document the middleware registration order in `configure.swift` — ordering is significant
- Keep migration filenames and DocC comments aligned — both identify the schema version
- Document `JobPayload` types for queued jobs — they are async API contracts

## Don'ts

- Don't skip validation documentation on `Content` models — Vapor validates on decode
- Don't document Vapor's built-in error types — document your app's custom `AbortError` subclasses only
