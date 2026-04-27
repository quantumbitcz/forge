# SwiftUI Framework Conventions

> Support tier: contract-verified

> Framework-specific conventions for SwiftUI iOS projects. Language idioms are in `modules/languages/swift.md`. Generic testing patterns are in `modules/testing/xctest.md`.

## Architecture (MVVM + SwiftUI)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `Views/` | SwiftUI views -- small, composable, declarative | ViewModels |
| `ViewModels/` | Presentation logic, state management | Services, Models |
| `Models/` | Data types, domain entities, Codable DTOs | -- |
| `Services/` | Networking, persistence, business logic | Models |
| `App/` | App entry point, navigation, dependency injection | all layers |

**Dependency rule:** Views depend only on ViewModels. ViewModels depend on Services and Models. No circular dependencies.

## SwiftUI Views

- **Small and composable.** Each view body under 50 lines. Extract subviews as separate structs.
- **No heavy computation in body.** Offload to ViewModel or use `.task {}` modifier.
- **Prefer composition over inheritance.** Combine small views, don't subclass.
- **Use ViewBuilder** for conditional content. Avoid `AnyView` -- erases type info, hurts performance.
- **Preview every view:** `#Preview { MyView() }` with mock data.

## MVVM Pattern

- ViewModels are `@Observable` classes (Swift 5.9+ / iOS 17+). For older targets, use `ObservableObject` with `@Published`.
- Views observe ViewModels via `@State` (for `@Observable`) or `@StateObject` / `@ObservedObject` (for `ObservableObject`).
- ViewModels expose read-only state + action methods. No `import SwiftUI` in ViewModels.

## Concurrency

- **async/await** for all asynchronous work. No completion handlers in new code.
- Use `Task { }` in view `.task {}` modifier or ViewModel action methods.
- Annotate ViewModels with `@MainActor` to ensure UI state updates on main thread.
- Use `actor` for thread-safe mutable state in services.
- No `DispatchQueue.main.async` in new code -- use `@MainActor` instead.

## Persistence

- **SwiftData** (iOS 17+) preferred. Use `@Model` macro for persistent types.
- **Core Data** for iOS 16 and below. Use `NSManagedObject` subclasses.
- Never access persistence layer directly from views -- go through a service/repository.

## Naming Patterns

| Artifact | Pattern | Example |
|----------|---------|---------|
| View | `{Feature}View` | `UserProfileView` |
| ViewModel | `{Feature}ViewModel` | `UserProfileViewModel` |
| Model | `{Entity}` | `User`, `Post` |
| Service | `{Domain}Service` | `AuthService`, `NetworkService` |
| Test | `{Subject}Tests` | `UserProfileViewModelTests` |

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels
- SwiftLint enforced: zero violations
- Use `guard` for early returns. Prefer `guard let` over nested `if let`
- Mark `@MainActor` on any type that touches UI state

## Error Handling

- Use typed errors conforming to `LocalizedError` for user-facing messages
- Network errors: map HTTP status codes to domain error types
- Show errors in UI via alert modifiers bound to ViewModel error state
- Never silently swallow errors. At minimum log via `os.Logger`

## Xcode Project Structure

Group by feature first, then by layer within each feature:
```
Features/{Feature}/Views/
Features/{Feature}/ViewModels/
Models/
Services/
```

## Networking / API Integration

- Create a single shared `URLSession` configuration for API base URL
- Use `async/await`: `try await URLSession.shared.data(for: request)`
- Validate HTTP status codes -- don't just check for `nil` error
- Implement retry logic for 429 and 5xx (exponential backoff, max 3)
- Cache responses with `URLCache` for GET requests

## Memory Safety

### Retain Cycles
- `[weak self]` in closures stored by other objects (delegates, timers, observers)
- Delegates as `weak var delegate: SomeDelegate?`
- Use Instruments > Leaks and Memory Graph Debugger to find cycles

### Value vs Reference Types
- Prefer `struct` for data models (value semantics, no retain cycles)
- Use `class` when: identity matters, inheritance needed, shared mutable state
- Use `actor` for thread-safe mutable state (Swift 5.5+)

## Dependency Management (SPM)

- Prefer SPM over CocoaPods/Carthage
- Pin to exact versions for release builds: `.exact("1.2.3")`
- Store `Package.resolved` in git for reproducible builds
- Prefer Apple-maintained packages when available

## Testing

### Test Framework
- **XCTest** for unit and integration tests; **Swift Testing** (`@Test`, `#expect`) for Swift 5.10+/Xcode 16+
- **ViewInspector** for SwiftUI view unit tests (inspect view hierarchy without running on device)
- **XCUITest** for end-to-end UI automation

### Integration Test Patterns
- Test ViewModels as plain Kotlin/Swift classes — inject mock services, verify state transitions
- Use `ViewInspector` to assert view content based on ViewModel state (loading, error, populated)
- Mock networking with `URLProtocol` subclass or protocol-based abstraction
- Use `@MainActor` test methods for ViewModel tests that update UI state

### What to Test
- ViewModel state transitions and business logic (primary focus)
- Service-layer networking: request construction, response parsing, error mapping
- Navigation: verify ViewModel emits correct navigation events
- Persistence: SwiftData/CoreData CRUD operations with in-memory store

### What NOT to Test
- SwiftUI renders views correctly (SwiftUI guarantees this)
- `@State` / `@Observable` reactivity mechanics — the framework handles this
- SPM dependency resolution
- Standard SwiftUI modifiers behavior (e.g., `.padding()`, `.font()`)

### Example Test Structure
```
Tests/
  ViewModelTests/
    UserProfileViewModelTests.swift  # ViewModel unit tests
  ServiceTests/
    AuthServiceTests.swift           # network/service tests
  UITests/
    UserProfileUITests.swift         # XCUITest end-to-end
  Mocks/
    MockAuthService.swift            # protocol-based mocks
```

For general XCTest patterns, see `modules/testing/xctest.md`.

## Smart Test Rules

- No duplicate tests — grep existing tests before writing new ones
- Test business behavior, not implementation details
- Do NOT test framework guarantees (e.g., SwiftUI renders views, `@State` updates trigger re-render)
- Do NOT test standard modifier behavior or SPM dependency resolution
- Each test scenario covers a unique code path
- Fewer meaningful tests > high coverage of trivial code

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated views, changing property wrapper contracts, restructuring navigation patterns.

## Dos and Don'ts

### Do
- Use `[weak self]` in closures stored by other objects
- Prefer `async/await` over completion handler chains
- Use `@MainActor` for all UI-updating code
- Use `Task { }` for launching async work from synchronous contexts
- Prefer `@Observable` macro (iOS 17+) over `ObservableObject` + `@Published`
- Keep view bodies under 30 lines

### Don't
- Don't force-unwrap (`!`) optionals unless guaranteed
- Don't use `unowned` unless reference will never outlive the owner
- Don't use `DispatchQueue.main.async` in SwiftUI -- use `@MainActor`
- Don't nest more than 3 levels of `if let` / `guard let`
- Don't use singletons for testable services -- use dependency injection
- Don't access `UIApplication.shared` in SwiftUI views -- use `@Environment`
