# Vapor + xcov

> Extends `modules/code-quality/xcov.md` with Vapor-specific integration.
> Generic xcov conventions (xcresult bundles, xcov gem, CI integration) are NOT repeated here.

## Integration Setup

Vapor projects run on Linux — use `swift test --enable-code-coverage` and LLVM toolchain rather than `xcodebuild`. The xcov gem and Xcode-based reporting are MacOS-only:

```yaml
# .github/workflows/test.yml — Linux-compatible (preferred for Vapor)
- name: Run tests with coverage
  run: swift test --enable-code-coverage

- name: Generate LCOV report
  run: |
    BIN_PATH=$(swift build --show-bin-path)
    xcrun llvm-cov export \
      "${BIN_PATH}/../debug/MyAppPackageTests.xctest/Contents/MacOS/MyAppPackageTests" \
      --instr-profile="${BIN_PATH}/../debug/codecov/default.profdata" \
      --format=lcov \
      --ignore-filename-regex="(Tests/|\.build/)" \
      > coverage.lcov

- name: Upload to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: coverage.lcov
    fail_ci_if_error: true
```

For MacOS CI with Xcode:

```yaml
- name: Run tests (Xcode)
  run: |
    xcodebuild test \
      -scheme MyApp \
      -destination "platform=MacOS" \
      -enableCodeCoverage YES \
      -resultBundlePath TestResults.xcresult
```

## Framework-Specific Patterns

### Testing Vapor Route Handlers

Use `XCTVapor` to exercise handlers through the full Vapor test stack. This is the primary coverage mechanism for Vapor controller code:

```swift
import XCTVapor

final class UserControllerTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        try await configure(app)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
    }

    func testCreateUser_returns201() async throws {
        try await app.test(.POST, "/api/users",
            headers: ["Content-Type": "application/json"],
            body: .init(string: """
                {"email": "alice@example.com", "name": "Alice"}
            """)
        ) { res async in
            XCTAssertEqual(res.status, .created)
            let response = try res.content.decode(UserResponse.self)
            XCTAssertEqual(response.email, "alice@example.com")
        }
    }

    func testCreateUser_returns409_onDuplicate() async throws {
        // Seed a user, then try to create duplicate
        try await seedUser(email: "alice@example.com")
        try await app.test(.POST, "/api/users",
            body: .init(string: """{"email": "alice@example.com", "name": "Alice"}""")
        ) { res async in
            XCTAssertEqual(res.status, .conflict)
        }
    }
}
```

Each `app.test(...)` call covers the route handler, middleware chain, DTO decoding, service, and repository code.

### Covering Middleware

Vapor middleware is only covered when a request passes through it. Test middleware via route tests with both passing and failing inputs:

```swift
func testAuthMiddleware_rejects_missingToken() async throws {
    try await app.test(.GET, "/api/protected") { res async in
        XCTAssertEqual(res.status, .unauthorized)
    }
}

func testAuthMiddleware_allows_validToken() async throws {
    let token = try await createTestToken()
    try await app.test(.GET, "/api/protected",
        headers: ["Authorization": "Bearer \(token)"]
    ) { res async in
        XCTAssertEqual(res.status, .ok)
    }
}
```

### Coverage Thresholds

Apply thresholds to controller, service, and repository packages — exclude migration files which contain boilerplate schema definitions:

```bash
# Exclude migrations from threshold calculation
xcrun llvm-cov export \
  "${BIN_PATH}/../debug/MyAppPackageTests.xctest/Contents/MacOS/MyAppPackageTests" \
  --instr-profile="${BIN_PATH}/../debug/codecov/default.profdata" \
  --format=lcov \
  --ignore-filename-regex="(Tests/|Migrations/|configure\.swift|routes\.swift)" \
  > coverage.lcov
```

### Fluent Migration Coverage

Fluent migration `prepare` and `revert` functions should be tested — they ensure the schema evolves correctly. Test them with the `.testing` environment backed by SQLite:

```swift
func testMigration_createsUsersTable() async throws {
    app = try await Application.make(.testing)
    app.databases.use(.sqlite(.memory), as: .sqlite)
    app.migrations.add(CreateUsersTable())
    try await app.autoMigrate()

    // Verify the table exists and accepts data
    let user = User(email: "test@example.com", name: "Test")
    try await user.save(on: app.db)
    XCTAssertNotNil(user.id)
}
```

## Additional Dos

- Use `XCTVapor` `app.test(...)` as the primary coverage driver — it exercises the full Vapor request pipeline and produces accurate coverage data for controllers and middleware.
- Test both success and error responses for every route — Vapor's error middleware converts `Abort` throws to HTTP status codes; all branches must be covered.
- Use `--ignore-filename-regex` to exclude `configure.swift` and `routes.swift` from thresholds — they contain wiring code, not testable business logic.

## Additional Don'ts

- Don't use `xcodebuild` for Vapor coverage in Linux CI — use `swift test --enable-code-coverage` and `llvm-cov` directly.
- Don't skip testing `revert()` in Fluent migrations — an untested `revert()` breaks rollback and leaves the database in an inconsistent state on migration failure.
- Don't set coverage thresholds above 80% for Vapor projects that use Fluent — ORM boilerplate (model field declarations, migrations) is difficult to cover without integration tests against a real database.
