# Fluent Migrations — Generic Patterns

## Overview

Fluent (Vapor's ORM) handles schema migrations via the `AsyncMigration` protocol. Migrations run in registration order and are tracked in a `_fluent_migrations` table. Use `swift run App migrate` to apply and `swift run App migrate --revert` to roll back.

## Core Patterns

### AsyncMigration Protocol
```swift
struct CreateOrder: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("orders")
            .id()
            .field("user_id",    .uuid,    .required, .references("users", "id", onDelete: .cascade))
            .field("total",      .double,  .required)
            .field("status",     .string,  .required, .sql(.default("pending")))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("orders").delete()
    }
}

// Additive migration — add column with default
struct AddOrderNotes: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("orders")
            .field("notes", .string)
            .update()
    }
    func revert(on database: Database) async throws {
        try await database.schema("orders")
            .deleteField("notes")
            .update()
    }
}
```

### Registration Order
```swift
// configure.swift — order matters; dependencies must be registered first
app.migrations.add(CreateUser())
app.migrations.add(CreateOrder())   // after CreateUser (FK dependency)
app.migrations.add(AddOrderNotes())
```

## Testing
- Use `app.autoRevert()` in test teardown to roll back migrations cleanly
- Test both `prepare()` and `revert()` for every migration
- Use an in-memory SQLite database for fast migration tests

## Dos
- Always implement `revert()` — enables clean teardown in test pipelines
- Register migrations in dependency order (parent tables before child tables)
- Prefer additive changes; rename via new column + data copy + drop old column pattern

## Don'ts
- Don't use `autoMigrate()` in production — use the `migrate` CLI command in deployment scripts
- Don't drop columns in the same migration that removes their references — do it in the next migration
- Don't skip testing `revert()` in CI — a broken revert blocks emergency rollbacks
