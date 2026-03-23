# SwiftUI + XCTest Testing Patterns

> SwiftUI-specific testing patterns for XCTest. Extends `modules/testing/xctest.md`.

## ViewModel Testing

- Test state transitions and action outcomes directly
- Mock services via protocols
- Assert `@Published` / `@Observable` state changes

```swift
@MainActor
final class UserProfileViewModelTests: XCTestCase {
    func testLoadProfile_success_updatesState() async {
        let mockService = MockUserService(user: .stub)
        let vm = UserProfileViewModel(userService: mockService)

        await vm.loadProfile(id: "123")

        XCTAssertEqual(vm.state, .loaded)
        XCTAssertEqual(vm.user?.name, "Alice")
    }
}
```

## Test Naming Convention

- Pattern: `test{Action}_{condition}_{expectedResult}`
- Example: `testLogin_withInvalidEmail_showsError`

## Service Testing

- Mock `URLProtocol` for network tests
- Test error mapping: HTTP status codes -> domain errors
- Test retry logic with simulated failures

## View Testing

- ViewInspector for snapshot/interaction tests (optional)
- XCUITest for critical user flows only (login, purchase, onboarding)
- Test `@Observable` / `ObservableObject` state changes via unit tests on ViewModel

## Mocking Pattern

- Define protocols for all services
- Create mock implementations in test target
- Inject via init parameters (not singletons)
- No network in tests -- mock all network calls
