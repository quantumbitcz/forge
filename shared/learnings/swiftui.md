---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
# Cross-Project Learnings: swiftui

## PREEMPT items

### SU-PREEMPT-001: Missing [weak self] in stored closures causes retain cycles
- **Domain:** memory
- **Pattern:** Closures stored in publishers, timers, NotificationCenter observers, or delegate callbacks capture `self` strongly, creating retain cycles that leak ViewModels and Services. Use `[weak self]` in all closures stored by other objects. Use `[unowned self]` only when the closure cannot outlive the owner.
- **Confidence:** HIGH
- **Hit count:** 0

### SU-PREEMPT-002: DispatchQueue.main.async used instead of @MainActor
- **Domain:** concurrency
- **Pattern:** Using `DispatchQueue.main.async` in SwiftUI code bypasses Swift's structured concurrency model, creating data race risks that the compiler cannot check. Use `@MainActor` annotation on ViewModels and `Task { @MainActor in ... }` for main-thread updates.
- **Confidence:** HIGH
- **Hit count:** 0

### SU-PREEMPT-003: AnyView erases type information and hurts diff performance
- **Domain:** performance
- **Pattern:** Using `AnyView` to erase view types (e.g., in conditional branches) prevents SwiftUI from efficiently diffing the view hierarchy, causing unnecessary redraws. Use `@ViewBuilder` for conditional content or `Group` with `if/else` to preserve concrete types.
- **Confidence:** HIGH
- **Hit count:** 0

### SU-PREEMPT-004: ObservableObject with @Published causes over-rendering
- **Domain:** performance
- **Pattern:** Every `@Published` property change triggers a view update for ALL views observing that ViewModel, even if they only use one property. With `@Observable` (iOS 17+), SwiftUI tracks which properties each view reads and only updates affected views. Prefer `@Observable` over `ObservableObject`.
- **Confidence:** HIGH
- **Hit count:** 0

### SU-PREEMPT-005: Heavy computation in view body blocks the main thread
- **Domain:** performance
- **Pattern:** SwiftUI re-evaluates `body` on every state change. Expensive computations (sorting, filtering, date formatting) in `body` cause UI jank. Move heavy work to ViewModel properties or use `.task {}` modifier for async computation. Cache results with `@State` or computed properties.
- **Confidence:** HIGH
- **Hit count:** 0

### SU-PREEMPT-006: Singletons for services prevent test isolation
- **Domain:** testing
- **Pattern:** Using `static let shared = MyService()` singletons makes it impossible to inject mock services in tests. Use protocol-based dependency injection: define a `protocol MyServiceProtocol`, inject it into ViewModels via constructor, and provide mocks in tests.
- **Confidence:** HIGH
- **Hit count:** 0

### SU-PREEMPT-007: NavigationLink destination is evaluated eagerly
- **Domain:** performance
- **Pattern:** `NavigationLink(destination: HeavyView())` instantiates `HeavyView` immediately, even before the user taps. Use `NavigationLink(value:)` with `.navigationDestination(for:)` (iOS 16+) for lazy destination evaluation, or wrap in `NavigationLazyView`.
- **Confidence:** MEDIUM
- **Hit count:** 0

### SU-PREEMPT-008: Force-unwrapping optionals crashes in production
- **Domain:** reliability
- **Pattern:** Using `!` to force-unwrap optionals causes runtime crashes when the value is nil. Use `guard let`, `if let`, or nil-coalescing (`??`) for safe unwrapping. Force-unwrap is acceptable only in `@IBOutlet` (UIKit) or when the value is guaranteed by construction (document the guarantee).
- **Confidence:** HIGH
- **Hit count:** 0
