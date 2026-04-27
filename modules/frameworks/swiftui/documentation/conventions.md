# SwiftUI Documentation Conventions

> Support tier: community

> Extends `modules/documentation/conventions.md` with SwiftUI-specific patterns.

## Code Documentation

- Use Swift DocC format (`///`) for all public `View` structs, `ObservableObject` classes, and protocol declarations.
- Views: document the primary purpose and non-obvious parameters. Avoid restating what Swift's type system already expresses.
- `@Observable` / `ObservableObject` classes: document published properties that represent significant state transitions.
- Preview macros (`#Preview`): keep preview code self-documenting with descriptive names — they serve as live documentation.
- SPM packages: every public symbol in a library target must have a DocC comment.

```swift
/// Displays the user's coaching session summary with progress indicators.
///
/// Fetches session data on appear via the injected ``SessionViewModel``.
/// Shows a loading skeleton while data is in-flight.
///
/// - Parameter sessionId: The unique identifier of the session to display.
public struct SessionSummaryView: View {
    let sessionId: Session.ID
    ...
}
```

## Architecture Documentation

- Document the navigation graph: which views are reachable from which, and via what mechanism (`NavigationStack`, sheet, fullScreenCover).
- Document the `@Environment` values in use across the app — list custom environment keys and what they carry.
- State ownership: document which `@Observable` objects are created at the root vs injected per-feature.
- Document SPM target dependencies and their public API contracts.

## Diagram Guidance

- **Navigation graph:** Mermaid flowchart showing view transitions and modal presentations.
- **State ownership:** Class diagram showing `@Observable` objects, their published state, and which views own vs observe them.

## Dos

- DocC comments on all public symbols in SPM library targets
- Document `@Environment` keys at their declaration site
- Keep `#Preview` names descriptive — they are the first doc developers read

## Don'ts

- Don't document `@State` private implementation details — focus on the view's observable behavior
- Don't use CocoaPods — SPM is canonical; document SPM package graph in architecture docs
