# Fluent ORM — Generic Persistence Patterns

## Overview

Fluent is the official ORM for the Vapor web framework (Swift). It provides a type-safe, database-agnostic query API backed by Swift's `async/await`. Fluent supports PostgreSQL, MySQL, SQLite, and MongoDB via driver packages. Models are defined with property wrappers and conform to `Model`.

## Architecture Patterns

### Model Design
```swift
final class User: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(format: .uuid)         var id: UUID?
    @Field(key: "email")       var email: String
    @Field(key: "name")        var name: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?   // soft delete

    // Relationships
    @Children(for: \.$user) var orders: [Order]

    init() {}
}

final class Order: Model, Content, @unchecked Sendable {
    static let schema = "orders"

    @ID(format: .uuid)        var id: UUID?
    @Parent(key: "user_id")   var user: User
    @Field(key: "total")      var total: Double

    init() {}
}
```

### Query Patterns
```swift
// Basic CRUD
let user   = try await User.find(id, on: db)
let users  = try await User.query(on: db).filter(\.$email == email).first()
let all    = try await User.query(on: db).sort(\.$createdAt, .descending).all()
try await user.save(on: db)
try await user.delete(on: db)

// Eager loading (prevents N+1)
let users = try await User.query(on: db).with(\.$orders).all()

// Pagination
let page = try await User.query(on: db).paginate(PageRequest(page: 1, per: 20))

// Batch insert
try await [user1, user2, user3].create(on: db)
```

### Transactions
```swift
try await db.transaction { txDb in
    try await order.save(on: txDb)
    try await inventory.update(on: txDb)
}
```

## Performance Considerations

- Use `with(\.$relation)` for all eager-loaded relationships — never access lazy `.value` outside request scope.
- Use `paginate()` for list queries; never load unbounded result sets.
- Use raw SQL via `db.raw()` for complex aggregations that Fluent's query builder cannot express efficiently.
- Index foreign key columns in migrations (`SchemaBuilder.index()`).

## Testing

```swift
// In-memory SQLite for unit tests
app.databases.use(.sqlite(.memory), as: .sqlite)
try await app.autoMigrate()
// ... test
try await app.autoRevert()
```

## Dos
- Use `@ID(format: .uuid)` for distributed-safe primary keys
- Always implement `revert()` in migrations for rollback support
- Use `db.transaction { }` for multi-model atomic writes
- Mark models `@unchecked Sendable` when property wrappers prevent compiler inference

## Don'ts
- Don't call `.value` on `@Parent`/`@Children` without eager loading — will crash at runtime
- Don't expose `Model` directly in API responses; always map to a `Content`-conforming DTO
- Don't use `autoMigrate()` in production startup; run migration commands in deployment pipelines
- Don't loop over collections calling `.find()` per item — use `whereIn` or batch queries
