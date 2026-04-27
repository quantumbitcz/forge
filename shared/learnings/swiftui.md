---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "su-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.823206Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["memory", "swiftui"]
    source: "cross-project"
    archived: false
    body_ref: "#su-preempt-001"
  - id: "su-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.823206Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "swiftui"]
    source: "cross-project"
    archived: false
    body_ref: "#su-preempt-002"
  - id: "su-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.823206Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["performance", "swiftui"]
    source: "cross-project"
    archived: false
    body_ref: "#su-preempt-003"
  - id: "su-preempt-004"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.823206Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["performance", "swiftui"]
    source: "cross-project"
    archived: false
    body_ref: "#su-preempt-004"
  - id: "su-preempt-005"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.823206Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["performance", "swiftui"]
    source: "cross-project"
    archived: false
    body_ref: "#su-preempt-005"
  - id: "su-preempt-006"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.823206Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["testing", "swiftui"]
    source: "cross-project"
    archived: false
    body_ref: "#su-preempt-006"
  - id: "su-preempt-007"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.823206Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["performance", "swiftui"]
    source: "cross-project"
    archived: false
    body_ref: "#su-preempt-007"
  - id: "su-preempt-008"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.823206Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["reliability", "swiftui"]
    source: "cross-project"
    archived: false
    body_ref: "#su-preempt-008"
---
# Cross-Project Learnings: swiftui

## PREEMPT items

### SU-PREEMPT-001: Missing [weak self] in stored closures causes retain cycles
<a id="su-preempt-001"></a>
- **Domain:** memory
- **Pattern:** Closures stored in publishers, timers, NotificationCenter observers, or delegate callbacks capture `self` strongly, creating retain cycles that leak ViewModels and Services. Use `[weak self]` in all closures stored by other objects. Use `[unowned self]` only when the closure cannot outlive the owner.
- **Confidence:** HIGH
- **Hit count:** 0

### SU-PREEMPT-002: DispatchQueue.main.async used instead of @MainActor
<a id="su-preempt-002"></a>
- **Domain:** concurrency
- **Pattern:** Using `DispatchQueue.main.async` in SwiftUI code bypasses Swift's structured concurrency model, creating data race risks that the compiler cannot check. Use `@MainActor` annotation on ViewModels and `Task { @MainActor in ... }` for main-thread updates.
- **Confidence:** HIGH
- **Hit count:** 0

### SU-PREEMPT-003: AnyView erases type information and hurts diff performance
<a id="su-preempt-003"></a>
- **Domain:** performance
- **Pattern:** Using `AnyView` to erase view types (e.g., in conditional branches) prevents SwiftUI from efficiently diffing the view hierarchy, causing unnecessary redraws. Use `@ViewBuilder` for conditional content or `Group` with `if/else` to preserve concrete types.
- **Confidence:** HIGH
- **Hit count:** 0

### SU-PREEMPT-004: ObservableObject with @Published causes over-rendering
<a id="su-preempt-004"></a>
- **Domain:** performance
- **Pattern:** Every `@Published` property change triggers a view update for ALL views observing that ViewModel, even if they only use one property. With `@Observable` (iOS 17+), SwiftUI tracks which properties each view reads and only updates affected views. Prefer `@Observable` over `ObservableObject`.
- **Confidence:** HIGH
- **Hit count:** 0

### SU-PREEMPT-005: Heavy computation in view body blocks the main thread
<a id="su-preempt-005"></a>
- **Domain:** performance
- **Pattern:** SwiftUI re-evaluates `body` on every state change. Expensive computations (sorting, filtering, date formatting) in `body` cause UI jank. Move heavy work to ViewModel properties or use `.task {}` modifier for async computation. Cache results with `@State` or computed properties.
- **Confidence:** HIGH
- **Hit count:** 0

### SU-PREEMPT-006: Singletons for services prevent test isolation
<a id="su-preempt-006"></a>
- **Domain:** testing
- **Pattern:** Using `static let shared = MyService()` singletons makes it impossible to inject mock services in tests. Use protocol-based dependency injection: define a `protocol MyServiceProtocol`, inject it into ViewModels via constructor, and provide mocks in tests.
- **Confidence:** HIGH
- **Hit count:** 0

### SU-PREEMPT-007: NavigationLink destination is evaluated eagerly
<a id="su-preempt-007"></a>
- **Domain:** performance
- **Pattern:** `NavigationLink(destination: HeavyView())` instantiates `HeavyView` immediately, even before the user taps. Use `NavigationLink(value:)` with `.navigationDestination(for:)` (iOS 16+) for lazy destination evaluation, or wrap in `NavigationLazyView`.
- **Confidence:** MEDIUM
- **Hit count:** 0

### SU-PREEMPT-008: Force-unwrapping optionals crashes in production
<a id="su-preempt-008"></a>
- **Domain:** reliability
- **Pattern:** Using `!` to force-unwrap optionals causes runtime crashes when the value is nil. Use `guard let`, `if let`, or nil-coalescing (`??`) for safe unwrapping. Force-unwrap is acceptable only in `@IBOutlet` (UIKit) or when the value is guaranteed by construction (document the guarantee).
- **Confidence:** HIGH
- **Hit count:** 0
