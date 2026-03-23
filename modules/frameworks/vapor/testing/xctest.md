# Vapor + XCTest Testing Patterns

> Vapor-specific testing patterns for XCTest. Extends `modules/testing/xctest.md`.

## Test Application Setup

- Use `Application.make(.testing)` to create a test app instance
- Configure in-memory SQLite or testcontainers PostgreSQL for CI
- Register test-specific middleware and routes

```swift
final class UserTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        try await configure(app)
        try await app.autoMigrate()
    }

    override func tearDown() async throws {
        try await app.autoRevert()
        try await app.asyncShutdown()
    }
}
```

## HTTP Request Testing

- Use `app.test(.GET, "/api/v1/users")` for integration tests
- Assert status codes, response body, headers

```swift
func testGetUsers_returnsOK() async throws {
    try await app.test(.GET, "/api/v1/users") { res async in
        XCTAssertEqual(res.status, .ok)
        let users = try res.content.decode([UserResponse].self)
        XCTAssertFalse(users.isEmpty)
    }
}
```

## Test Naming

- Pattern: `test{Action}_{condition}_{expectedResult}`
- Example: `testCreateUser_withValidInput_returns201`

## Database Testing

- Use in-memory SQLite for fast local tests
- Use testcontainers PostgreSQL in CI for production-like testing
- Each test should start with a clean state (autoMigrate/autoRevert)
- Use factory helpers for creating test entities
