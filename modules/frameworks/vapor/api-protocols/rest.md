# Vapor REST — API Protocol Binding

## Integration Setup

```swift
// Package.swift — Vapor is the only dependency needed for REST
.product(name: "Vapor", package: "vapor"),
```

```swift
// routes.swift
func routes(_ app: Application) throws {
    let todos = app.grouped("api", "v1", "todos")
    todos.get(use: TodoController().index)
    todos.post(use: TodoController().create)
    todos.group(":todoID") { todo in
        todo.get(use: TodoController().show)
        todo.put(use: TodoController().update)
        todo.delete(use: TodoController().delete)
    }
}
```

## Framework-Specific Patterns

### RouteCollection
```swift
struct TodoController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let todos = routes.grouped("todos")
        todos.get(use: index)
        todos.post(use: create)
        todos.group(":todoID") { todo in
            todo.get(use: show)
            todo.put(use: update)
            todo.delete(use: delete)
        }
    }

    func index(req: Request) async throws -> [TodoResponse] {
        try await Todo.query(on: req.db).all().map(TodoResponse.init)
    }

    func create(req: Request) async throws -> Response {
        let input = try req.content.decode(CreateTodoRequest.self)
        let todo = Todo(title: input.title)
        try await todo.save(on: req.db)
        return try await todo.encodeResponse(status: .created, for: req)
    }
}
```

### Content Protocol (DTO)
```swift
struct CreateTodoRequest: Content {
    var title: String
    var completed: Bool?
}

struct TodoResponse: Content {
    var id: UUID
    var title: String
    var completed: Bool
}
```

### Error Middleware
```swift
// configure.swift
app.middleware.use(ErrorMiddleware.default(environment: app.environment))

// Custom abort
guard let todo = try await Todo.find(id, on: req.db) else {
    throw Abort(.notFound, reason: "Todo not found")
}
```

### Async/Await vs EventLoopFuture
Prefer `async throws` handlers in Vapor 4.x+ — `EventLoopFuture` is legacy and should only be used
when wrapping third-party libraries that do not yet expose async APIs.

## Scaffolder Patterns

```yaml
patterns:
  controller: "Sources/App/Controllers/{Entity}Controller.swift"
  dto:        "Sources/App/DTOs/{Entity}DTO.swift"
  routes:     "Sources/App/routes.swift"
  error_middleware: "Sources/App/Middleware/ErrorMiddleware.swift"
```

## Additional Dos/Don'ts

- DO use `RouteCollection` to group related endpoints; register via `try app.register(collection:)`
- DO decode request bodies with `req.content.decode(T.self)` — Vapor validates `Content-Type` automatically
- DO return `Response` with explicit status for creation/deletion; use `Abort` for errors
- DO use `async throws` handlers; avoid `EventLoopFuture` in new code
- DON'T put database queries directly in `routes.swift` — delegate to controllers or use cases
- DON'T swallow errors silently; let them propagate to `ErrorMiddleware`
- DON'T return raw `Model` types from endpoints — always project to `Content`-conforming DTOs
