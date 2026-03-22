# Swift/Vapor Agent Conventions Reference

> Full details in project CLAUDE.md. This is a curated subset for agent consumption.

## Architecture (Repository Pattern)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `Sources/App/Controllers/` | Route handlers, request validation, response mapping | Models, Repositories, DTOs |
| `Sources/App/Models/` | Fluent models, migrations | Fluent |
| `Sources/App/Repositories/` | Data access abstraction (protocol + Fluent impl) | Models |
| `Sources/App/DTOs/` | Request/response types conforming to `Content` | — |
| `Sources/App/Middleware/` | Cross-cutting concerns (auth, logging, error handling) | Vapor |
| `Sources/App/Migrations/` | Database schema migrations | Fluent |
| `Tests/AppTests/` | XCTest-based integration and unit tests | App, XCTVapor |

**Dependency rule:** Controllers never access the database directly. All data access goes through repository protocols. Models are shared across layers.

## Route Handlers

- Route registration in `routes.swift` or dedicated `RouteCollection` conformances.
- Group related routes: `app.grouped("api", "v1", "users")`.
- Use `req.content.decode(CreateUserDTO.self)` for request parsing.
- Return `Content`-conforming types directly — Vapor handles JSON encoding.
- Always validate input: use `Validatable` protocol or manual checks before processing.

## Fluent ORM

- Models are `final class` conforming to `Model` and `Content` (where appropriate).
- Use `@ID(key: .id)` with `UUID` for primary keys.
- Field property wrappers: `@Field`, `@OptionalField`, `@Timestamp`, `@Parent`, `@Children`, `@Siblings`.
- Eager-load relationships explicitly: `User.query(on: db).with(\.$posts).all()`.
- Never use raw SQL unless Fluent query builder is insufficient — document the reason.

## Content Protocol

- All request/response DTOs conform to `Content` (which implies `Codable`).
- Separate DTOs from models: `CreateUserDTO`, `UpdateUserDTO`, `UserResponse`.
- Use `CodingKeys` to decouple JSON field names from Swift property names when needed.
- Validate DTOs via `Validatable`: `ValidationsOf<CreateUserDTO>`.

## Middleware

- Custom middleware conforms to `AsyncMiddleware`.
- Error middleware: catch domain errors and map to appropriate HTTP responses.
- Auth middleware: `req.auth.require(User.self)` after `UserAuthenticator`.
- Order matters: register error middleware before route-specific middleware.

## Async/Await

- All route handlers, repository methods, and middleware use `async throws` — no `EventLoopFuture`.
- Use `Task` for fire-and-forget background work, but prefer queues (Vapor Queues) for reliability.
- Avoid blocking calls on the event loop: no `Thread.sleep`, no synchronous I/O.

## Environment & Configuration

- Use `Environment.get("DATABASE_URL")` or `.env` file for secrets.
- Configure in `configure.swift`: database, middleware stack, migrations, routes.
- Never hardcode credentials or connection strings.

## Naming Patterns

| Artifact | Pattern | Example |
|----------|---------|---------|
| Controller | `{Entity}Controller` | `UserController`, `PostController` |
| Model | `{Entity}` | `User`, `Post`, `Comment` |
| DTO (request) | `Create{Entity}DTO`, `Update{Entity}DTO` | `CreateUserDTO` |
| DTO (response) | `{Entity}Response` | `UserResponse` |
| Repository protocol | `{Entity}Repository` | `UserRepository` |
| Repository impl | `Fluent{Entity}Repository` | `FluentUserRepository` |
| Migration | `Create{Entity}` | `CreateUser`, `AddEmailToUser` |
| Middleware | `{Purpose}Middleware` | `AuthMiddleware`, `RateLimitMiddleware` |
| Test | `{Entity}Tests` | `UserTests`, `AuthTests` |

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels.
- SwiftLint enforced: `swiftlint lint` must pass with zero violations.
- Use `guard` for early returns. Prefer `guard let` over nested `if let`.
- Mark thrown errors with descriptive types: `throw Abort(.notFound, reason: "User not found")`.
- Access control: default to `internal`. Use `public` only for package API, `private` for implementation details.

## Error Handling

| Domain Error | HTTP Status | Vapor Mapping |
|-------------|-------------|---------------|
| Not found | 404 | `Abort(.notFound)` |
| Validation failure | 400 | `Abort(.badRequest, reason:)` |
| Unauthorized | 401 | `Abort(.unauthorized)` |
| Forbidden | 403 | `Abort(.forbidden)` |
| Conflict / duplicate | 409 | `Abort(.conflict, reason:)` |
| Internal error | 500 | `Abort(.internalServerError)` |

## Testing

- **Framework:** `XCTVapor` (built on XCTest) for integration tests.
- **Test app:** `Application.make(.testing)` + `app.test(.GET, "/api/v1/users")`.
- **Database:** Use in-memory SQLite or Testcontainers for PostgreSQL in CI.
- **Naming:** `test{Action}_{condition}_{expectedResult}` (e.g., `testCreateUser_withValidInput_returns201`).
- **Coverage:** test all happy paths and key error paths per endpoint.

## Migrations

- One migration per structural change. Never modify an existing migration after deployment.
- Name describes the change: `CreateUser`, `AddAvatarURLToUser`.
- Use `SchemaBuilder`: `database.schema("users").id().field("name", .string, .required).create()`.
- Reverse migration in `revert(on:)` for rollback support.

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated files, changing APIs, fixing pre-existing bugs.
