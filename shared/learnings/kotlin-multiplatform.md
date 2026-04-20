---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
# Cross-Project Learnings: kotlin-multiplatform

## PREEMPT items

### KM-PREEMPT-001: JVM-only libraries in commonMain break iOS/JS compilation
- **Domain:** build
- **Pattern:** Adding Gson, Jackson, Hilt, Room, or RxJava to `commonMain` dependencies compiles fine for JVM but fails on iOS and JS targets. Use `kotlinx.serialization` for serialization, Koin for DI, and cross-platform persistence libraries in `commonMain`.
- **Confidence:** HIGH
- **Hit count:** 0

### KM-PREEMPT-002: Dispatchers.Main in commonMain is platform-specific
- **Domain:** concurrency
- **Pattern:** `Dispatchers.Main` requires a platform-specific implementation (Android Main Looper, not available on iOS without extra setup). Using it directly in `commonMain` causes `IllegalStateException` on iOS. Inject dispatchers via DI or `expect`/`actual`.
- **Confidence:** HIGH
- **Hit count:** 0

### KM-PREEMPT-003: expect/actual overuse when interface+DI suffices
- **Domain:** architecture
- **Pattern:** Using `expect`/`actual` for platform variation that could be an interface injected via Koin creates untestable code. Reserve `expect`/`actual` for platform primitives (UUID, logging, secure storage). Use interfaces + DI for services and repositories.
- **Confidence:** HIGH
- **Hit count:** 0

### KM-PREEMPT-004: Missing actual implementation on one target breaks allTests
- **Domain:** build
- **Pattern:** Every `expect` declaration must have a matching `actual` in ALL configured platform source sets. A missing `actual` in `iosMain` that was only tested on Android causes `./gradlew allTests` to fail. Run `allTests` in CI for every PR.
- **Confidence:** HIGH
- **Hit count:** 0

### KM-PREEMPT-005: Flow bridging to Swift requires SKIE or manual wrapper
- **Domain:** interop
- **Pattern:** Kotlin `Flow` is not directly usable from Swift. Without SKIE or a manual `StateFlowWrapper` that bridges to `AsyncSequence`, iOS developers get a raw `KotlinFlow` object they cannot collect. Set up SKIE or provide explicit wrappers for all exposed flows.
- **Confidence:** HIGH
- **Hit count:** 0

### KM-PREEMPT-006: GlobalScope in shared code leaks coroutines across platform lifecycles
- **Domain:** concurrency
- **Pattern:** Using `GlobalScope.launch` in `commonMain` creates coroutines that outlive the screen/activity lifecycle. Tie coroutine scopes to platform lifecycle boundaries (ViewModel scope on Android, Swift task scope on iOS) and inject them into shared code.
- **Confidence:** HIGH
- **Hit count:** 0

### KM-PREEMPT-007: MockK may not work on Kotlin/Native targets in commonTest
- **Domain:** testing
- **Pattern:** MockK relies on JVM-specific reflection and does not fully support Kotlin/Native. Tests using MockK in `commonTest` fail on iOS targets. Use hand-written fakes or interface stubs for tests that must run cross-platform.
- **Confidence:** HIGH
- **Hit count:** 0

### KM-PREEMPT-008: Kotlin version and KMP library version matrix mismatch
- **Domain:** build
- **Pattern:** KMP libraries (Ktor, kotlinx.serialization, Compose Multiplatform) must be compatible with the Kotlin compiler version. Upgrading Kotlin without updating all KMP library versions causes mysterious compilation failures. Pin all versions to a compatible matrix.
- **Confidence:** MEDIUM
- **Hit count:** 0
