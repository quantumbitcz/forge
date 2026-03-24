# PostgreSQL with Vapor

## Integration Setup

```swift
// Package.swift
.package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.9.0"),
// targets:
.product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
```

```swift
// configure.swift
app.databases.use(
    .postgres(
        hostname: Environment.get("DB_HOST") ?? "localhost",
        port:     Environment.get("DB_PORT").flatMap(Int.init) ?? 5432,
        username: Environment.get("DB_USER") ?? "vapor",
        password: Environment.get("DB_PASS") ?? "",
        database: Environment.get("DB_NAME") ?? "vapor_db",
        tlsConfiguration: .makeClientConfiguration()     // enable TLS in production
    ),
    as: .psql
)
```

## Framework-Specific Patterns

### Connection Pool Configuration
```swift
// Customize pool size via SQLPostgresConfiguration
var config = SQLPostgresConfiguration(
    hostname: hostname, port: port,
    username: username, password: password, database: database
)
config.connectTimeout = .seconds(30)
// Pool size defaults to event-loop count; increase for high-throughput workloads
app.databases.use(.postgres(configuration: config, maxConnectionsPerEventLoop: 2), as: .psql)
```

### Testcontainers / Testing
```swift
// Tests/AppTests/AppTests.swift
override func setUp() async throws {
    app = try await Application.make(.testing)
    app.databases.use(.postgres(hostname: "localhost", port: 5433,
                                username: "test", password: "test",
                                database: "test_db"), as: .psql)
    try await app.autoMigrate()
}
override func tearDown() async throws {
    try await app.autoRevert()
    await app.asyncShutdown()
}
```

## Scaffolder Patterns

```yaml
patterns:
  configure:    "Sources/App/configure.swift"
  migration:    "Sources/App/Migrations/Create{Entity}.swift"
  model:        "Sources/App/Models/{Entity}.swift"
  env_example:  ".env.example"
```

## Additional Dos/Don'ts

- DO use environment variables for all connection credentials; never hardcode
- DO set `maxConnectionsPerEventLoop` based on measured connection saturation
- DO enable TLS (`tlsConfiguration`) for all production connections
- DO run `app.autoMigrate()` at startup only in development; use explicit migration commands in production
- DON'T use `fallbackToDestructiveMigration()` outside ephemeral test environments
- DON'T share a single `EventLoop` across the entire app — Vapor's pool manages per-loop connections automatically
