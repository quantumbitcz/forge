# Fluent ORM with Vapor

## Integration Setup

```swift
// Package.swift
.product(name: "Fluent", package: "fluent"),
.product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
// or FluentSQLiteDriver / FluentMySQLDriver
```

## Framework-Specific Patterns

### Model Definition
```swift
import Fluent, Vapor

final class Todo: Model, Content, @unchecked Sendable {
    static let schema = "todos"

    @ID(format: .uuid)        var id: UUID?
    @Field(key: "title")      var title: String
    @Field(key: "completed")  var completed: Bool
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    // Relation: @Parent, @Children, @Siblings
    @Parent(key: "user_id")   var user: User

    init() {}
    init(id: UUID? = nil, title: String, completed: Bool = false, userID: User.IDValue) {
        self.id = id
        self.title = title
        self.completed = completed
        self.$user.id = userID
    }
}
```

### Query API
```swift
// Eager loading to avoid N+1
let todos = try await Todo.query(on: db)
    .with(\.$user)
    .filter(\.$completed == false)
    .sort(\.$createdAt, .descending)
    .paginate(PageRequest(page: 1, per: 20))

// Batch save
try await todos.create(on: db)

// Soft delete (requires @Timestamp(key: "deleted_at", on: .delete))
try await todo.delete(on: db)           // sets deleted_at
try await todo.delete(force: true, on: db) // hard delete
```

### Transactions
```swift
try await db.transaction { txDb in
    let order = Order(userID: userID, total: total)
    try await order.save(on: txDb)
    try await orderItems.create(on: txDb)
}
```

## Scaffolder Patterns

```yaml
patterns:
  model:     "Sources/App/Models/{Entity}.swift"
  migration: "Sources/App/Migrations/Create{Entity}.swift"
  controller: "Sources/App/Controllers/{Entity}Controller.swift"
```

## Additional Dos/Don'ts

- DO use `@ID(format: .uuid)` for all primary keys; avoid auto-increment in distributed systems
- DO use `with(\.$relation)` for eager loading; never access lazy relations outside the request context
- DO use `db.transaction { }` for multi-model atomic operations
- DO mark models `@unchecked Sendable` when Fluent property wrappers prevent compiler inference
- DON'T call `Model.find` in a loop — compose queries or use `whereIn`
- DON'T store domain logic in Model — keep models as data containers; use services/use-cases
- DON'T expose `@Parent` foreign key IDs directly in responses; project to DTOs
