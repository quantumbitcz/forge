# XCTest Testing Conventions

## Test Structure

Subclass `XCTestCase`. Group related tests in one class per feature or service. Use `// MARK: -` sections to separate logical groups within a class. Place unit tests in `{Target}Tests/` and UI tests in `{Target}UITests/`.

```swift
class UserServiceTests: XCTestCase {
    var sut: UserService!
    var mockRepo: MockUserRepository!

    override func setUpWithError() throws {
        mockRepo = MockUserRepository()
        sut = UserService(repository: mockRepo)
    }
}
```

## Naming

- Class: `{Subject}Tests`
- Method: `test_{action}_{context}__{expectation}` or `test_{plainEnglishDescription}`
- All test methods must start with `test` — XCTest discovers them by prefix

```swift
func test_createUser_withValidEmail_returnsNewUser() { }
func test_login_whenPasswordIsWrong_throwsAuthError() { }
```

## Assertions / Matchers

```swift
XCTAssertEqual(result, expected)
XCTAssertTrue(condition)
XCTAssertFalse(condition)
XCTAssertNil(value)
XCTAssertNotNil(value)
XCTAssertGreaterThan(a, b)
XCTAssertThrowsError(try riskyCall()) { error in
    XCTAssertEqual(error as? AppError, .unauthorized)
}
XCTAssertNoThrow(try safeCall())
```

Add the `message` parameter for non-obvious assertions — it appears in the failure output.

## Lifecycle

```swift
override func setUpWithError() throws {
    // Called before each test — throws version preferred
}
override func tearDownWithError() throws {
    sut = nil   // break reference cycles
}

// Async variants (Xcode 14+)
override func setUp() async throws { }
override func tearDown() async throws { }
```

Use `addTeardownBlock` for inline cleanup co-located with the setup that requires it.

## Async Testing

```swift
// Modern: async/await (preferred for iOS 15+)
func test_fetchProfile_returnsData() async throws {
    let profile = try await sut.fetchProfile(userId: "u1")
    XCTAssertEqual(profile.name, "Alice")
}

// Legacy: XCTestExpectation
func test_callbackFires() {
    let exp = expectation(description: "completion fires")
    sut.load { _ in exp.fulfill() }
    waitForExpectations(timeout: 2)
}
```

Prefer `async throws` tests over expectations for new code.

## @MainActor Tests

When the SUT is `@MainActor`, annotate the test class or individual methods:

```swift
@MainActor
class ViewModelTests: XCTestCase { ... }
```

## Mocking

No built-in mock framework. Patterns:
- **Protocol stubs** — hand-roll a `MockXxx: XxxProtocol` for simple cases
- **Sourcery / Swift Mockery** — generate mocks for large interfaces
- Inject dependencies via initializer — never reach into global singletons

## UI Testing

```swift
let app = XCUIApplication()
app.launch()
app.buttons["Login"].tap()
XCTAssertTrue(app.staticTexts["Welcome"].exists)
app.textFields["Email"].typeText("user@example.com")
```

Use accessibility identifiers (`accessibilityIdentifier`) over labels for stable selectors.

## What NOT to Test

- SwiftUI `View` body layout — test ViewModel logic separately
- Auto-synthesized `Codable` conformance on simple models
- `didSet` observers that only call `setNeedsLayout`
- OS-level lifecycle callbacks (e.g., `applicationDidBecomeActive`)

## Anti-Patterns

- `sleep(1)` — use expectations or async/await
- Force-unwrapping (`!`) in test setup — use `XCTUnwrap` instead
- One massive test method covering multiple scenarios
- Sharing `sut` state across test methods without reset in `setUp`
- Asserting on view hierarchy strings for business logic verification
