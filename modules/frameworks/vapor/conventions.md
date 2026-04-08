# Vapor Framework Conventions

> Framework-specific conventions for Vapor projects. Language idioms are in `modules/languages/swift.md`. Generic testing patterns are in `modules/testing/xctest.md`.

## Architecture (Repository Pattern)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `Controllers/` | Route handlers, request validation, response mapping | Models, Repositories, DTOs |
| `Models/` | Persistence models, migrations | Depends on `persistence:` choice |
| `Repositories/` | Data access abstraction (protocol + persistence impl) | Models |
| `DTOs/` | Request/response types conforming to `Content` | -- |
| `Middleware/` | Cross-cutting concerns (auth, logging, error handling) | Vapor |
| `Migrations/` | Database schema migrations | Depends on `persistence:` choice |

**Dependency rule:** Controllers never access the database directly. All data access goes through repository protocols.

## Route Handlers

- Route registration in `routes.swift` or dedicated `RouteCollection` conformances
- Group related routes: `app.grouped("api", "v1", "users")`
- Use `req.content.decode(CreateUserDTO.self)` for request parsing
- Return `Content`-conforming types directly -- Vapor handles JSON encoding
- Always validate input: use `Validatable` protocol or manual checks

## Data Access

> Specific ORM patterns (Fluent, etc.) are in the `persistence/` binding files. This section covers generic data access conventions.

- Models use UUID primary keys
- Eager-load relationships explicitly to prevent N+1 queries
- Prefer the persistence layer's query builder over raw SQL
- See the persistence binding file for model definition, property wrappers, and query patterns specific to your `persistence:` choice

## Content Protocol

- All request/response DTOs conform to `Content` (which implies `Codable`)
- Separate DTOs from models: `CreateUserDTO`, `UpdateUserDTO`, `UserResponse`
- Use `CodingKeys` to decouple JSON field names from Swift property names
- Validate DTOs via `Validatable`: `ValidationsOf<CreateUserDTO>`

## Middleware

- Custom middleware conforms to `AsyncMiddleware`
- Error middleware: catch domain errors and map to HTTP responses
- Auth middleware: `req.auth.require(User.self)` after `UserAuthenticator`
- Order matters: register error middleware before route-specific middleware

## Async/Await

- All route handlers, repository methods, and middleware use `async throws`
- No `EventLoopFuture` in new code
- Use `Task` for fire-and-forget background work, prefer Vapor Queues for reliability
- Avoid blocking calls on the event loop: no `Thread.sleep`, no synchronous I/O

## Naming Patterns

| Artifact | Pattern | Example |
|----------|---------|---------|
| Controller | `{Entity}Controller` | `UserController` |
| Model | `{Entity}` | `User`, `Post` |
| DTO (request) | `Create{Entity}DTO` | `CreateUserDTO` |
| DTO (response) | `{Entity}Response` | `UserResponse` |
| Repository protocol | `{Entity}Repository` | `UserRepository` |
| Repository impl | `{Persistence}{Entity}Repository` | `PostgresUserRepository` |
| Migration | `Create{Entity}` | `CreateUser` |
| Middleware | `{Purpose}Middleware` | `AuthMiddleware` |

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels
- SwiftLint enforced: zero violations
- Use `guard` for early returns. Prefer `guard let` over nested `if let`
- Mark thrown errors with descriptive types: `throw Abort(.notFound, reason: "User not found")`

## Error Handling

| Domain Error | HTTP Status | Vapor Mapping |
|-------------|-------------|---------------|
| Not found | 404 | `Abort(.notFound)` |
| Validation failure | 400 | `Abort(.badRequest, reason:)` |
| Unauthorized | 401 | `Abort(.unauthorized)` |
| Forbidden | 403 | `Abort(.forbidden)` |
| Conflict | 409 | `Abort(.conflict, reason:)` |

## Migrations

- One migration per structural change. Never modify an existing migration after deployment
- Use the persistence layer's migration API (see persistence binding file for syntax)
- Always implement reverse/revert migrations for rollback support

## Query Optimization

- Eager-load relationships to prevent N+1 queries (syntax depends on `persistence:` choice)
- Use joins for multi-table queries instead of multiple round trips
- Use batch operations for bulk inserts — avoid individual saves in a loop

## Security

- Auth validation via middleware: `req.auth.require(User.self)`
- Environment-based configuration: `Environment.get("DATABASE_URL")`
- Never hardcode credentials or connection strings
- Use structured logging: `req.logger` with metadata

## Testing

### Test Framework
- **XCTest** for unit and integration tests; **Swift Testing** (`@Test`, `#expect`) for Swift 5.10+
- **XCTVapor** (built into Vapor) for in-process HTTP testing without a running server

### Integration Test Patterns
- Use `Application.testable()` to create an in-process test app — no TCP server needed
- Use `app.test(.GET, "/api/v1/users")` to test full request/response cycles through middleware and routes
- Configure an in-memory database for fast test execution (depends on `persistence:` choice)
- Use **Testcontainers** for integration tests requiring a real PostgreSQL instance

### What to Test
- Route handler contracts: status codes, JSON response shapes, validation errors
- Repository logic: CRUD operations and query correctness against a test database
- Middleware behavior: auth rejection, error transformation
- Service-layer business rules with mocked repository protocols
- Model validation: test `Validatable` conformance for DTOs

### What NOT to Test
- Vapor routes requests to the correct handler (Vapor guarantees this)
- Persistence model property wrapper behavior (tested by the library vendor)
- `Content` protocol encoding/decoding for standard types
- `Abort` produces the correct HTTP status code — Vapor handles this

### Example Test Structure
```
Tests/AppTests/
  Controllers/
    UserControllerTests.swift      # XCTVapor integration tests
  Services/
    UserServiceTests.swift         # unit tests with mocked repos
  Repositories/
    UserRepositoryTests.swift      # in-memory DB tests
  Helpers/
    TestApplication.swift          # shared test app factory
```

For general XCTest patterns, see `modules/testing/xctest.md`.

## Smart Test Rules

- No duplicate tests — grep existing tests before writing new ones
- Test business behavior, not implementation details
- Do NOT test framework guarantees (e.g., Vapor routes requests correctly, `Abort` maps to HTTP status)
- Do NOT test persistence model property wrapper behavior or `Content` encoding for standard types
- Each test scenario covers a unique code path
- Fewer meaningful tests > high coverage of trivial code

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated controllers, changing route contracts, restructuring middleware chains.

## Dos and Don'ts

### Do
- Use `async/await` for all route handlers (Vapor 4.50+)
- Use `Content` protocol for request/response DTOs
- Use `app.middleware.use()` for cross-cutting concerns
- Use `req.logger` with structured metadata for tracing
- Group routes with `app.grouped("api", "v1")` for versioning

### Don't
- Don't use `EventLoopFuture` chains in new code -- use `async/await`
- Don't access `app` properties from within route handlers -- use `req.application`
- Don't return persistence models directly from routes -- use DTOs
- Don't use force-try (`try!`) -- handle errors with proper do-catch
