# Vapor Framework Conventions

> Framework-specific conventions for Vapor projects. Language idioms are in `modules/languages/swift.md`. Generic testing patterns are in `modules/testing/xctest.md`.

## Architecture (Repository Pattern)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `Controllers/` | Route handlers, request validation, response mapping | Models, Repositories, DTOs |
| `Models/` | Fluent models, migrations | Fluent |
| `Repositories/` | Data access abstraction (protocol + Fluent impl) | Models |
| `DTOs/` | Request/response types conforming to `Content` | -- |
| `Middleware/` | Cross-cutting concerns (auth, logging, error handling) | Vapor |
| `Migrations/` | Database schema migrations | Fluent |

**Dependency rule:** Controllers never access the database directly. All data access goes through repository protocols.

## Route Handlers

- Route registration in `routes.swift` or dedicated `RouteCollection` conformances
- Group related routes: `app.grouped("api", "v1", "users")`
- Use `req.content.decode(CreateUserDTO.self)` for request parsing
- Return `Content`-conforming types directly -- Vapor handles JSON encoding
- Always validate input: use `Validatable` protocol or manual checks

## Fluent ORM

- Models are `final class` conforming to `Model` and `Content` (where appropriate)
- Use `@ID(key: .id)` with `UUID` for primary keys
- Field property wrappers: `@Field`, `@OptionalField`, `@Timestamp`, `@Parent`, `@Children`, `@Siblings`
- Eager-load relationships explicitly: `User.query(on: db).with(\.$posts).all()`
- Never use raw SQL unless Fluent query builder is insufficient

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
| Repository impl | `Fluent{Entity}Repository` | `FluentUserRepository` |
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
- Use `SchemaBuilder`: `database.schema("users").id().field("name", .string, .required).create()`
- Reverse migration in `revert(on:)` for rollback support

## Query Optimization

- Use `.with(\.$relation)` for eager loading to prevent N+1 queries
- Use `.join()` for multi-table queries instead of multiple round trips
- Batch operations: use `.create(on:)` with arrays, not individual `.save(on:)`

## Security

- Auth validation via middleware: `req.auth.require(User.self)`
- Environment-based configuration: `Environment.get("DATABASE_URL")`
- Never hardcode credentials or connection strings
- Use structured logging: `req.logger` with metadata

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

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
- Don't return Fluent models directly from routes -- use DTOs
- Don't use force-try (`try!`) -- handle errors with proper do-catch
