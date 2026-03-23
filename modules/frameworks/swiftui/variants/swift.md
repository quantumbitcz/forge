# SwiftUI + Swift Variant

> Swift-specific patterns for SwiftUI projects. Extends `modules/languages/swift.md` and `modules/frameworks/swiftui/conventions.md`.

## Observable Pattern Choice

### iOS 17+ (Observation framework)
- Use `@Observable` macro on ViewModel classes
- Views observe via `@State` (owned) or let binding (external)
- No need for `@Published` -- all stored properties are automatically observed

### iOS 16 and below (Combine)
- Use `ObservableObject` with `@Published` properties
- Views observe via `@StateObject` (owned) or `@ObservedObject` (external)
- Store Combine subscriptions in `Set<AnyCancellable>`

## Combine Usage

- Use Combine publishers for reactive data streams (search debouncing, real-time updates)
- Prefer `async/await` over Combine for one-shot operations
- Use `.debounce()`, `.removeDuplicates()`, `.map()` for search-as-you-type

## SwiftData Patterns

- Use `@Model` macro for persistent types
- Access via `@Query` in views or through a repository service
- Prefer lightweight migration when possible

## Navigation

- Use `NavigationStack` with `navigationDestination(for:)` for value-based navigation
- Store navigation path in ViewModel for programmatic navigation
- Use `@Environment(\.dismiss)` for dismissing sheets/navigation

## Accessibility

- VoiceOver labels on all meaningful UI elements
- Dynamic Type: test with largest accessibility sizes
- Use `accessibilityLabel`, `accessibilityHint`, `accessibilityValue`
- Support Dark Mode and Increased Contrast
