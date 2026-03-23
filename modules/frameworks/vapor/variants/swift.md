# Vapor + Swift Variant

> Swift-specific patterns for Vapor projects. Extends `modules/languages/swift.md` and `modules/frameworks/vapor/conventions.md`.

## Environment and Configuration

- Use `Environment.get("KEY")` or `.env` file for secrets
- Configure in `configure.swift`: database, middleware stack, migrations, routes
- Never hardcode credentials or connection strings

## Protocol-Based Repositories

- Define repository protocols at the consumer (controller) side
- Fluent implementations conform to the protocol
- Enables easy swapping for testing (in-memory, mock)

```swift
protocol UserRepository {
    func find(_ id: UUID, on db: Database) async throws -> User?
    func save(_ user: User, on db: Database) async throws
}

struct FluentUserRepository: UserRepository {
    func find(_ id: UUID, on db: Database) async throws -> User? {
        try await User.find(id, on: db)
    }
}
```

## Access Control

- Default to `internal` access level
- Use `public` only for package API
- Use `private` for implementation details
- Use `fileprivate` sparingly

## Structured Logging

- Use `req.logger` with metadata for request-scoped logging
- Include operation, entity ID, user context in metadata
- Never use `print()` in production code

## Codable Patterns

- DTOs conform to `Content` (which implies `Codable`)
- Use `CodingKeys` when JSON field names differ from Swift property names
- Use `@Timestamp` for automatic created_at/updated_at handling
