# Vapor + swiftlint

> Extends `modules/code-quality/swiftlint.md` with Vapor-specific integration.
> Generic swiftlint conventions (installation, rule categories, CI integration) are NOT repeated here.

## Integration Setup

For Vapor SPM projects, add SwiftLint as a build tool plugin or run it as a separate CI step. On Linux CI (where Vapor servers often run), install via apt or binary:

```yaml
# .github/workflows/quality.yml — macOS runner for lint
- name: SwiftLint
  run: swiftlint lint --reporter github-actions-logging --strict

# Or on Linux runner
- name: Install and run SwiftLint
  run: |
    curl -Lo swiftlint.zip https://github.com/realm/SwiftLint/releases/latest/download/swiftlint_linux.zip
    unzip swiftlint.zip -d swiftlint-bin
    ./swiftlint-bin/swiftlint lint --reporter json | tee swiftlint-report.json
```

`.swiftlint.yml` for Vapor projects:

```yaml
opt_in_rules:
  - force_unwrapping
  - missing_docs
  - strict_fileprivate
  - empty_xctest_method
  - closure_spacing
  - closure_end_indentation

disabled_rules:
  - todo            # allow TODO comments in routes.swift and feature work

included:
  - Sources
  - Tests

excluded:
  - .build
  - Sources/App/Migrations   # migration files have boilerplate patterns

function_body_length:
  warning: 40
  error: 80    # route handlers must stay thin

type_body_length:
  warning: 200
  error: 400
```

## Framework-Specific Patterns

### Async Handler Patterns

Vapor 4 handlers are `async throws` functions. `force_try` and `force_unwrapping` are both prohibited — use `try await` and `guard let` patterns:

```swift
// Bad — force_try in route handler
func getUser(_ req: Request) async throws -> UserResponse {
    let id = try! req.parameters.require("id", as: UUID.self) // flagged

// Good — proper error propagation
func getUser(_ req: Request) async throws -> UserResponse {
    let id = try req.parameters.require("id", as: UUID.self)
    guard let user = try await userRepository.find(id, on: req.db) else {
        throw Abort(.notFound, reason: "User \(id) not found")
    }
    return UserResponse(user)
}
```

### req.db Access Rules

Direct `req.db` access in handlers violates the repository pattern. SwiftLint custom rules can flag this:

```yaml
# .swiftlint.yml
custom_rules:
  direct_db_in_controller:
    name: "Direct DB Access in Controller"
    regex: 'func .+\(_ req: Request\)[\s\S]*?req\.db'
    message: "Controllers must not access req.db directly. Use a repository."
    severity: warning
    included: ".*Controllers.*\\.swift"
```

Route handlers should receive repository protocols, not direct database access:

```swift
// Good — repository injected via app services
func listUsers(_ req: Request) async throws -> [UserResponse] {
    let repo = req.userRepository          // injected via Application extension
    let users = try await repo.all(on: req.db)
    return users.map(UserResponse.init)
}
```

### Fluent Model Conventions

Fluent models with property wrappers (`@ID`, `@Field`, `@Parent`) must not use `force_unwrapping` on optional fields:

```swift
// Bad — force unwrap on Fluent relationship
func handler(_ req: Request) async throws -> Response {
    let user = try await User.find(id, on: req.db)!  // flagged

// Good
guard let user = try await User.find(id, on: req.db) else {
    throw Abort(.notFound)
}
```

Custom SwiftLint rule to flag model boilerplate:

```yaml
custom_rules:
  fluent_model_force_unwrap:
    name: "Fluent Force Unwrap"
    regex: 'User\.find\(.*\)!'
    message: "Use guard let or try await with explicit error handling for Fluent queries."
    severity: error
```

### Content Protocol DTOs

DTOs conforming to Vapor's `Content` protocol should have explicit `CodingKeys` and validation. SwiftLint's `missing_docs` rule applies to public DTO types in API packages:

```swift
/// The request body for creating a new user.
struct CreateUserDTO: Content, Validatable {
    /// The user's email address. Must be a valid email format.
    let email: String
    /// The user's display name. Between 2 and 50 characters.
    let name: String

    static func validations(_ validations: inout Validations) {
        validations.add("email", as: String.self, is: .email)
        validations.add("name", as: String.self, is: .count(2...50))
    }
}
```

## Additional Dos

- Enable `force_unwrapping` as an error (not just warning) for Vapor projects — a force unwrap in a request handler crashes the entire server worker, not just the request.
- Apply `function_body_length: warning: 40` for controller files — Vapor handlers that exceed 40 lines signal business logic leaking into the controller layer.
- Use custom SwiftLint rules to enforce repository pattern — direct `req.db` access in controllers is a common architectural violation.

## Additional Don'ts

- Don't disable `missing_docs` for public DTO types — Vapor API DTOs are the interface contract for API consumers and must be documented.
- Don't suppress `force_try` in route handler files — Vapor's error middleware converts `throws` to HTTP error responses; propagate errors with `try`, not `try!`.
- Don't apply `--fix` / `autocorrect` in CI — it mutates source files; use it locally only.
