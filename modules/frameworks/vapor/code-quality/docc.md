# Vapor + DocC

> Extends `modules/code-quality/docc.md` with Vapor-specific integration.
> Generic DocC conventions (installation, symbol docs, CI integration) are NOT repeated here.

## Integration Setup

DocC is most valuable for Vapor library packages and shared middleware/service modules. App-level `Sources/App/` code is typically not documented via DocC. Use the swift-docc-plugin for SPM packages:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
    .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
],
```

```yaml
# .github/workflows/docs.yml
- name: Generate DocC
  run: |
    swift package \
      --allow-writing-to-directory ./docs \
      generate-documentation \
      --target MyVaporLibrary \
      --output-path ./docs \
      --transform-for-static-hosting \
      --hosting-base-path MyVaporLibrary
```

## Framework-Specific Patterns

### API Endpoint Documentation

Document route controllers with the HTTP method, path, authentication requirement, and request/response types. Use `no_run` for examples that require a running server:

```swift
/// Handles user management endpoints at `/api/v1/users`.
///
/// ## Routes
///
/// | Method | Path              | Handler         | Auth Required |
/// |--------|-------------------|-----------------|---------------|
/// | GET    | `/users`          | ``index(_:)``   | Yes           |
/// | POST   | `/users`          | ``create(_:)``  | No            |
/// | GET    | `/users/:userID`  | ``show(_:)``    | Yes           |
/// | PUT    | `/users/:userID`  | ``update(_:)``  | Yes (owner)   |
/// | DELETE | `/users/:userID`  | ``delete(_:)``  | Yes (admin)   |
///
/// Register with:
///
/// ```swift
/// try app.register(collection: UserController())
/// ```
public struct UserController: RouteCollection {
```

### Documenting Individual Route Handlers

Each `async throws` handler must document its request parameters, body, success response, and all thrown `Abort` errors:

```swift
/// Creates a new user account.
///
/// Decodes a ``CreateUserDTO`` from the request body and creates a
/// persistent user record.
///
/// - Parameter req: The incoming Vapor request.
/// - Returns: A ``UserResponse`` with the created user's data.
/// - Throws: ``Abort/conflict`` (409) if the email is already registered.
/// - Throws: ``Abort/badRequest`` (400) if the request body fails validation.
///
/// # Request Body
///
/// ```json
/// {
///   "email": "alice@example.com",
///   "name": "Alice"
/// }
/// ```
///
/// # Response
///
/// HTTP 201 with:
///
/// ```json
/// { "id": "uuid", "email": "alice@example.com", "name": "Alice" }
/// ```
public func create(_ req: Request) async throws -> UserResponse {
```

### Documenting Route Group Registration

Document `RouteCollection.boot(routes:)` with the mounted path and middleware applied to the group:

```swift
/// Registers all user routes under the `/api/v1/users` path.
///
/// Applied middleware:
/// - ``AuthMiddleware`` — validates Bearer token for authenticated routes
/// - ``RateLimitMiddleware`` — 100 requests/minute per IP
///
/// # Route Tree
///
/// ```
/// GET    /api/v1/users           — list users
/// POST   /api/v1/users           — create user (public)
/// GET    /api/v1/users/:userID   — get user
/// PUT    /api/v1/users/:userID   — update user (owner only)
/// DELETE /api/v1/users/:userID   — delete user (admin only)
/// ```
public func boot(routes: RoutesBuilder) throws {
```

### Documenting Fluent Models

Fluent `Model` types are the persistence contract — document all fields with their database column names, constraints, and relationship semantics:

```swift
/// A persistent user account record.
///
/// Stored in the `users` table. Created by ``UserController/create(_:)``
/// and read by ``UserRepository``.
///
/// ## Relationships
///
/// - ``posts`` — all posts authored by this user (lazy-loaded)
/// - ``profile`` — the user's extended profile (optional, eager-loadable)
///
/// ## Fields
///
/// | Swift Property | Column       | Type    | Constraints        |
/// |----------------|--------------|---------|--------------------|
/// | `id`           | `id`         | UUID    | primary key        |
/// | `email`        | `email`      | String  | unique, not null   |
/// | `name`         | `name`       | String  | not null           |
/// | `createdAt`    | `created_at` | Date?   | auto-set by Fluent |
public final class User: Model, Content {
```

### Documenting Middleware

Vapor middleware applied to route groups must document what it injects into `Request.storage`, its rejection conditions, and the authentication scheme:

```swift
/// Validates the Bearer token in the `Authorization` header and stores
/// the authenticated user in `Request.storage`.
///
/// Access the authenticated user in route handlers:
///
/// ```swift
/// let user = try req.auth.require(User.self)
/// ```
///
/// Rejects requests with HTTP 401 if:
/// - The `Authorization` header is absent
/// - The token is malformed (not `Bearer <token>`)
/// - The JWT signature is invalid or expired
///
/// Apply to protected route groups:
///
/// ```swift
/// let protected = routes.grouped(AuthMiddleware())
/// protected.get("profile", use: showProfile)
/// ```
public struct AuthMiddleware: AsyncMiddleware {
```

## Additional Dos

- Document all `Abort` throws with their HTTP status codes — API consumers need to know which error responses to handle without inspecting source code.
- Create a top-level article in the `.docc` catalog describing the API's authentication scheme and base URL — this is the first thing API consumers need.
- Document Fluent model fields with their database column names — the mapping between Swift properties and SQL columns is not obvious from the `@Field("column_name")` wrappers in all cases.

## Additional Don'ts

- Don't generate DocC for `Sources/App/configure.swift` and `Sources/App/routes.swift` — these are wiring code, not API documentation.
- Don't omit the `# Request Body` and `# Response` sections from handler docs — JSON structure is invisible from Swift types alone to HTTP API consumers.
- Don't use DocC articles as a substitute for OpenAPI/Swagger for REST APIs consumed by non-Swift clients — generate OpenAPI specs in addition to DocC for cross-language consumers.
