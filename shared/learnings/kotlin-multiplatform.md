---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "km-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.765789Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["build", "kotlin", "multiplatform"]
    source: "cross-project"
    archived: false
    body_ref: "km-preempt-001"
  - id: "km-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.765789Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "kotlin", "multiplatform"]
    source: "cross-project"
    archived: false
    body_ref: "km-preempt-002"
  - id: "km-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.765789Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["architecture", "kotlin", "multiplatform"]
    source: "cross-project"
    archived: false
    body_ref: "km-preempt-003"
  - id: "km-preempt-004"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.765789Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["build", "kotlin", "multiplatform"]
    source: "cross-project"
    archived: false
    body_ref: "km-preempt-004"
  - id: "km-preempt-005"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.765789Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["interop", "kotlin", "multiplatform"]
    source: "cross-project"
    archived: false
    body_ref: "km-preempt-005"
  - id: "km-preempt-006"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.765789Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "kotlin", "multiplatform"]
    source: "cross-project"
    archived: false
    body_ref: "km-preempt-006"
  - id: "km-preempt-007"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.765789Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["testing", "kotlin", "multiplatform"]
    source: "cross-project"
    archived: false
    body_ref: "km-preempt-007"
  - id: "km-preempt-008"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.765789Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["build", "kotlin", "multiplatform"]
    source: "cross-project"
    archived: false
    body_ref: "km-preempt-008"
---
# Cross-Project Learnings: kotlin-multiplatform

## PREEMPT items

### KM-PREEMPT-001: JVM-only libraries in commonMain break iOS/JS compilation
<a id="km-preempt-001"></a>
- **Domain:** build
- **Pattern:** Adding Gson, Jackson, Hilt, Room, or RxJava to `commonMain` dependencies compiles fine for JVM but fails on iOS and JS targets. Use `kotlinx.serialization` for serialization, Koin for DI, and cross-platform persistence libraries in `commonMain`.
- **Confidence:** HIGH
- **Hit count:** 0

### KM-PREEMPT-002: Dispatchers.Main in commonMain is platform-specific
<a id="km-preempt-002"></a>
- **Domain:** concurrency
- **Pattern:** `Dispatchers.Main` requires a platform-specific implementation (Android Main Looper, not available on iOS without extra setup). Using it directly in `commonMain` causes `IllegalStateException` on iOS. Inject dispatchers via DI or `expect`/`actual`.
- **Confidence:** HIGH
- **Hit count:** 0

### KM-PREEMPT-003: expect/actual overuse when interface+DI suffices
<a id="km-preempt-003"></a>
- **Domain:** architecture
- **Pattern:** Using `expect`/`actual` for platform variation that could be an interface injected via Koin creates untestable code. Reserve `expect`/`actual` for platform primitives (UUID, logging, secure storage). Use interfaces + DI for services and repositories.
- **Confidence:** HIGH
- **Hit count:** 0

### KM-PREEMPT-004: Missing actual implementation on one target breaks allTests
<a id="km-preempt-004"></a>
- **Domain:** build
- **Pattern:** Every `expect` declaration must have a matching `actual` in ALL configured platform source sets. A missing `actual` in `iosMain` that was only tested on Android causes `./gradlew allTests` to fail. Run `allTests` in CI for every PR.
- **Confidence:** HIGH
- **Hit count:** 0

### KM-PREEMPT-005: Flow bridging to Swift requires SKIE or manual wrapper
<a id="km-preempt-005"></a>
- **Domain:** interop
- **Pattern:** Kotlin `Flow` is not directly usable from Swift. Without SKIE or a manual `StateFlowWrapper` that bridges to `AsyncSequence`, iOS developers get a raw `KotlinFlow` object they cannot collect. Set up SKIE or provide explicit wrappers for all exposed flows.
- **Confidence:** HIGH
- **Hit count:** 0

### KM-PREEMPT-006: GlobalScope in shared code leaks coroutines across platform lifecycles
<a id="km-preempt-006"></a>
- **Domain:** concurrency
- **Pattern:** Using `GlobalScope.launch` in `commonMain` creates coroutines that outlive the screen/activity lifecycle. Tie coroutine scopes to platform lifecycle boundaries (ViewModel scope on Android, Swift task scope on iOS) and inject them into shared code.
- **Confidence:** HIGH
- **Hit count:** 0

### KM-PREEMPT-007: MockK may not work on Kotlin/Native targets in commonTest
<a id="km-preempt-007"></a>
- **Domain:** testing
- **Pattern:** MockK relies on JVM-specific reflection and does not fully support Kotlin/Native. Tests using MockK in `commonTest` fail on iOS targets. Use hand-written fakes or interface stubs for tests that must run cross-platform.
- **Confidence:** HIGH
- **Hit count:** 0

### KM-PREEMPT-008: Kotlin version and KMP library version matrix mismatch
<a id="km-preempt-008"></a>
- **Domain:** build
- **Pattern:** KMP libraries (Ktor, kotlinx.serialization, Compose Multiplatform) must be compatible with the Kotlin compiler version. Upgrading Kotlin without updating all KMP library versions causes mysterious compilation failures. Pin all versions to a compatible matrix.
- **Confidence:** MEDIUM
- **Hit count:** 0
