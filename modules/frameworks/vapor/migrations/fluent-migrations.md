# Fluent Migrations with Vapor

## Integration Setup

```swift
// configure.swift — register migrations
app.migrations.add(CreateTodo())
app.migrations.add(AddTodoNotes())  // subsequent migrations

// Run at startup (dev only) or via CLI
try await app.autoMigrate()

// CLI
swift run App migrate           // apply pending
swift run App migrate --revert  // revert last batch
```

## Framework-Specific Patterns

### AsyncMigration Protocol
```swift
struct CreateTodo: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("todos")
            .id()                                           // UUID primary key
            .field("title",      .string,  .required)
            .field("completed",  .bool,    .required, .sql(.default(false)))
            .field("user_id",    .uuid,    .required,
                   .references("users", "id", onDelete: .cascade))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("todos").delete()
    }
}

// Additive migration (add column)
struct AddTodoNotes: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("todos")
            .field("notes", .string)
            .update()
    }
    func revert(on database: Database) async throws {
        try await database.schema("todos")
            .deleteField("notes")
            .update()
    }
}
```

### SchemaBuilder Reference
```swift
.field("status", .string, .required, .sql(.default("pending")))
.unique(on: "email")
.foreignKey("role_id", references: "roles", "id", onDelete: .setNull)
.index("created_at")                    // single-column index
.index("user_id", "status")             // composite index
```

## Scaffolder Patterns

```yaml
patterns:
  migration: "Sources/App/Migrations/{ActionDescription}.swift"
  # Example: CreateTodo.swift, AddTodoNotes.swift, RenameColumnX.swift
```

## Additional Dos/Don'ts

- DO always implement `revert()` — enables clean rollback in staging/test pipelines
- DO register migrations in chronological order in `configure.swift`
- DO prefer additive changes (add columns, add tables) over destructive ones
- DON'T rename columns directly — add new column, migrate data, drop old column in separate migrations
- DON'T use `autoMigrate()` in production startup — run `migrate` command explicitly in deployment scripts
- DON'T share migration state between environments by resetting without reverting first
