# Vapor + swift-format

> Extends `modules/code-quality/swift-format.md` with Vapor-specific integration.
> Generic swift-format conventions (installation, configuration, CI integration) are NOT repeated here.

## Integration Setup

Vapor projects run on Linux (production) and MacOS (development). Install swift-format via SPM toolchain or Mint for consistent versions across both platforms:

```bash
# MacOS
brew install swift-format

# Linux CI
apt-get install -y swift-format   # or via toolchain
# Or build from source matching Swift toolchain version
```

```yaml
# .github/workflows/quality.yml
- name: swift-format lint
  run: swift-format lint --recursive --strict Sources/ Tests/

- name: swift-format check (CI gate)
  run: |
    swift-format format --recursive --dry-run Sources/ Tests/ 2>&1 | tee /tmp/fmt-diff
    [ ! -s /tmp/fmt-diff ] || (cat /tmp/fmt-diff; exit 1)
```

## Framework-Specific Patterns

### Formatting Route Registrations

Vapor route registration in `routes.swift` uses `RouteCollection` conformances with method chaining. swift-format handles these consistently — do not manually break route chains:

```swift
// swift-format normalizes route registration
func boot(routes: RoutesBuilder) throws {
    let users = routes.grouped("users")
    users.get(use: index)
    users.post(use: create)
    users.group(":userID") { user in
        user.get(use: show)
        user.put(use: update)
        user.delete(use: delete)
    }
}
```

Set `lineLength: 100` — Vapor route group chains with middleware and path components can be verbose:

```json
{
  "version": 1,
  "lineLength": 100,
  "indentation": { "spaces": 4 },
  "respectsExistingLineBreaks": true,
  "rules": {
    "OrderedImports": true,
    "UseTripleSlashForDocumentationComments": true,
    "FileScopedDeclarationPrivacy": true,
    "NeverForceUnwrap": true,
    "NeverUseForceTry": true,
    "AlwaysUseLowerCamelCase": true
  }
}
```

### Async Handler Formatting

Vapor `async throws` handlers benefit from consistent indentation of `guard let` chains. Let swift-format manage indentation — do not use `#[rustfmt::skip]` equivalent (`// swift-format-ignore`) for handler functions:

```swift
// Formatted by swift-format
func createUser(_ req: Request) async throws -> UserResponse {
    let dto = try req.content.decode(CreateUserDTO.self)
    try dto.validate(content: req)
    guard let existing = try await userRepo.findByEmail(dto.email, on: req.db) else {
        let user = try await userRepo.create(from: dto, on: req.db)
        return UserResponse(user)
    }
    throw Abort(.conflict, reason: "Email already registered")
}
```

### Formatting Fluent Migrations

Fluent migration files have schema builder chains (`database.schema(...)`) that are formatted vertically by swift-format. Let the formatter manage these chains:

```swift
// swift-format formats schema builders consistently
func prepare(on database: Database) async throws {
    try await database.schema("users")
        .id()
        .field("email", .string, .required)
        .field("name", .string, .required)
        .field("created_at", .datetime)
        .unique(on: "email")
        .create()
}
```

Exclude migration files from `NeverForceUnwrap` — Fluent's `@ID` macro sometimes requires `!` on property access during migration construction.

### Linux Compatibility

swift-format versions must match the Swift toolchain version on Linux CI. Pin the version:

```bash
# Verify swift-format matches Swift toolchain
swift --version
swift-format --version
```

Mismatched versions can produce different formatting output between MacOS dev machines and Linux CI, causing spurious diff failures.

## Additional Dos

- Pin swift-format to the same version as the production Swift toolchain — version mismatches between MacOS (dev) and Linux (CI) produce inconsistent formatting.
- Enable `NeverForceUnwrap: true` — Vapor server crashes from force unwraps affect all concurrent requests, not just the failing one.
- Run `swift-format format --in-place` in pre-commit hooks scoped to staged Swift files only — prevents diff noise from reformatting unrelated files.

## Additional Don'ts

- Don't run swift-format on Fluent-generated migration stubs (if using `vapor migration`) — generated code may not be idiomatic and reformatting can break it.
- Don't disable `OrderedImports` — Vapor files import `Vapor`, `Fluent`, `FluentPostgresDriver`, and custom modules; alphabetical ordering reduces merge conflicts.
- Don't use swift-format without SwiftLint — swift-format handles formatting/whitespace only; SwiftLint covers idiomatic patterns like `force_unwrapping` and `missing_docs` that swift-format ignores.
