# Swift/iOS Agent Conventions Reference

> Full details in project CLAUDE.md. This is a curated subset for agent consumption.

## Architecture (MVVM + SwiftUI)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `Views/` | SwiftUI views — small, composable, declarative | ViewModels |
| `ViewModels/` | Presentation logic, state management, Combine/Observable | Services, Models |
| `Models/` | Data types, domain entities, Codable DTOs | — |
| `Services/` | Networking, persistence, business logic | Models |
| `App/` | App entry point, navigation, dependency injection | all layers |
| `Tests/` | XCTest + ViewInspector unit and UI tests | App |

**Dependency rule:** Views depend only on ViewModels. ViewModels depend on Services and Models. Services depend on Models. No circular dependencies.

## SwiftUI Views

- **Small and composable.** Each view body should be under 50 lines. Extract subviews as separate structs.
- **No heavy computation in body.** View body is called frequently; offload work to ViewModel or use `.task {}` modifier.
- **Prefer composition over inheritance.** Build complex layouts by combining small views, not by subclassing.
- **Use ViewBuilder** for conditional content. Avoid `AnyView` — it erases type information and hurts performance.
- **Preview every view:** `#Preview { MyView() }` with mock data.

## MVVM Pattern

- ViewModels are `@Observable` classes (Swift 5.9+ / iOS 17+). For older targets, use `ObservableObject` with `@Published`.
- Views observe ViewModels via `@State` (for `@Observable`) or `@StateObject` / `@ObservedObject` (for `ObservableObject`).
- ViewModels expose:
  - Read-only state properties for the view to display.
  - Action methods the view calls on user interaction.
  - No `import SwiftUI` in ViewModels — they must be UI-framework agnostic.

## Concurrency

- **async/await** for all asynchronous work. No completion handlers in new code.
- Use `Task { }` in view `.task {}` modifier or ViewModel `init` / action methods.
- Annotate ViewModels with `@MainActor` to ensure UI state updates on the main thread.
- Use `actor` for thread-safe mutable state in services.
- No `DispatchQueue.main.async` in new code — use `@MainActor` instead.

## Combine

- Use `Combine` publishers for reactive data streams (e.g., search debouncing, real-time updates).
- Store subscriptions in `Set<AnyCancellable>` (or use `@Observable` pattern to avoid).
- Prefer `async/await` over Combine for one-shot operations.

## Persistence

- **SwiftData** (iOS 17+) preferred. Use `@Model` macro for persistent types.
- **Core Data** for iOS 16 and below. Use `NSManagedObject` subclasses.
- Never access persistence layer directly from views — go through a service or repository.
- Migrations: use lightweight migration when possible; document manual migration steps.

## Naming Patterns

| Artifact | Pattern | Example |
|----------|---------|---------|
| View | `{Feature}View` | `UserProfileView`, `SettingsView` |
| ViewModel | `{Feature}ViewModel` | `UserProfileViewModel` |
| Model | `{Entity}` | `User`, `Post`, `Message` |
| Service | `{Domain}Service` | `AuthService`, `NetworkService` |
| Repository | `{Entity}Repository` | `UserRepository` |
| DTO | `{Entity}DTO` or `{Entity}Response` | `UserDTO`, `LoginResponse` |
| Test | `{Subject}Tests` | `UserProfileViewModelTests` |

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels.
- SwiftLint enforced: `swiftlint lint` must pass with zero violations.
- Use `guard` for early returns. Prefer `guard let` over nested `if let`.
- Access control: default to `internal`. Use `public` for framework API, `private` for implementation details, `fileprivate` sparingly.
- Mark `@MainActor` on any type that touches UI state.

## Error Handling

- Use typed errors conforming to `LocalizedError` for user-facing messages.
- Network errors: map HTTP status codes to domain error types.
- Show errors in UI via alert modifiers: `.alert(isPresented:)` bound to ViewModel error state.
- Never silently swallow errors. At minimum log via `os.Logger`.

## Xcode Project Structure

```
MyApp/
  App/
    MyAppApp.swift        # @main entry point
    ContentView.swift     # Root navigation
  Features/
    {Feature}/
      Views/
      ViewModels/
  Models/
  Services/
  Resources/
    Assets.xcassets
    Localizable.xcstrings
```

Group by feature first, then by layer within each feature.

## Testing

- **Framework:** XCTest for unit tests, XCUITest for UI tests.
- **ViewModel tests:** test state transitions and action outcomes. Mock services via protocols.
- **View tests:** ViewInspector for snapshot/interaction tests (optional). UI tests via XCUITest for critical flows.
- **Naming:** `test{Action}_{condition}_{expectedResult}` (e.g., `testLogin_withInvalidEmail_showsError`).
- **No network in tests:** mock all network calls via protocol-based dependency injection.

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated files, changing APIs, fixing pre-existing bugs.

## Dos and Don'ts

### Do
- Use `[weak self]` in closures stored by other objects (delegates, timers, notification observers)
- Prefer `async/await` over completion handler chains for readability
- Use `@MainActor` for all UI-updating code
- Use `Codable` for JSON parsing — implement custom `CodingKeys` when API field names differ
- Use `Task { }` for launching async work from synchronous contexts (button taps, lifecycle methods)
- Prefer `@Observable` macro (iOS 17+) over `ObservableObject` + `@Published` for new code
- Use `swift-format` or `SwiftLint` with project-specific rules
- Keep view bodies under 30 lines — extract sub-views for independent sections

### Don't
- Don't force-unwrap (`!`) optionals unless the value is guaranteed (e.g., `IBOutlet` after `viewDidLoad`)
- Don't use `unowned` unless you can prove the reference will never outlive the owner — `weak` is safer
- Don't store closures that capture `self` without `[weak self]` — causes retain cycles
- Don't use `DispatchQueue.main.async` in SwiftUI — use `@MainActor` or `MainActor.run`
- Don't nest more than 3 levels of `if let` / `guard let` — use early returns
- Don't use singletons for testable services — use dependency injection (protocol + init parameter)
- Don't access `UIApplication.shared` in SwiftUI views — use `@Environment` values instead

## Memory Safety

### Retain Cycles
- **Closures stored in properties:** Always capture `[weak self]` or `[unowned self]`
- **Timer callbacks:** Timer retains its target — use `[weak self]` or invalidate timer in `deinit`
- **Delegate patterns:** Declare delegates as `weak var delegate: SomeDelegate?`
- **Notification observers:** Use block-based API with `[weak self]`, or use Combine publishers
- **Detection:** Use Instruments > Leaks and Memory Graph Debugger to find cycles

### Value vs Reference Types
- Prefer `struct` for data models (value semantics, no retain cycles)
- Use `class` when: identity matters, inheritance needed, or shared mutable state required
- Use `actor` for thread-safe mutable state (Swift 5.5+)

## Dependency Management (SPM)

### Swift Package Manager
- Prefer SPM over CocoaPods/Carthage for new projects
- Pin to exact versions for release builds: `.exact("1.2.3")`
- Use `.upToNextMinor` for development: allows patch updates
- Store `Package.resolved` in git for reproducible builds
- For local packages during development: use `path:` dependency, switch to remote before merge

### Adding Dependencies
- Evaluate: maintenance activity, issue count, Swift version compatibility, binary size impact
- Prefer Apple-maintained packages when available (e.g., `swift-collections`, `swift-algorithms`)
- Avoid dependencies for simple utilities — write your own if < 50 lines

## Networking / API Integration

### URLSession Patterns
- Create a single shared `URLSession` configuration for your API base URL
- Use `async/await` wrappers: `let (data, response) = try await URLSession.shared.data(for: request)`
- Validate HTTP status codes — don't just check for `nil` error
- Implement retry logic for 429 and 5xx responses (exponential backoff, max 3)
- Cache responses with `URLCache` for GET requests

### Error Handling for Network
- Map HTTP errors to domain-specific error enum (`.unauthorized`, `.notFound`, `.serverError`)
- Show user-friendly error messages — never expose raw HTTP status codes
- Implement offline detection and queuing for write operations

## Testing Strategy

### What to Test
- View models / presenters: business logic, state transitions, formatting
- Services: API integration with mocked URLProtocol
- Navigation: screen flow logic
- Accessibility: VoiceOver labels, dynamic type scaling

### SwiftUI Testing
- Use `@ViewInspector` or snapshot testing for UI verification
- Test `@Observable` / `ObservableObject` state changes directly (unit tests)
- E2E with XCUITest for critical user flows only (login, purchase, onboarding)
