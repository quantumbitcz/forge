# Kotlin Multiplatform Framework Conventions

> Language-agnostic KMP patterns. Language-specific Kotlin idioms are in `modules/languages/kotlin.md`.
> Framework-language integration is in `variants/kotlin.md`.

## Architecture (Shared + Platform)

| Module | Responsibility | Source Sets |
|--------|---------------|-------------|
| `shared/commonMain` | Domain models, use cases, repositories, networking, serialization | Kotlin stdlib, Ktor, kotlinx.serialization |
| `shared/androidMain` | Android-specific `actual` implementations, Android platform integrations | Android SDK |
| `shared/iosMain` | iOS-specific `actual` implementations, Darwin platform integrations | Darwin/Foundation |
| `shared/jsMain` | Web-specific `actual` implementations | Browser APIs |
| `shared/wasmMain` | Wasm-specific `actual` implementations | Wasm APIs |
| `androidApp/` | Android UI (Activity, Compose, ViewModels) | Android SDK, Compose, Hilt |
| `iosApp/` | iOS UI (SwiftUI, UIKit) | Swift, SwiftUI |

**Dependency rule:** `commonMain` must never import platform-specific APIs directly. All platform variation goes through `expect`/`actual` or interfaces injected via DI. Platform modules depend on `commonMain`, not the reverse.

## Source Sets and Dependencies

- `commonMain`: shared business logic, domain models, Ktor client, `kotlinx.serialization`, `kotlinx.coroutines`
- `commonTest`: shared tests runnable on all platforms (Kotest, `kotlinx-coroutines-test`)
- `androidMain` / `androidUnitTest` / `androidInstrumentedTest`: Android-specific implementations
- `iosMain` / `iosTest`: iOS-specific actual implementations
- HMPP (Hierarchical Multiplatform): use intermediate source sets (`mobileMain`, `nativeMain`) to share code between a subset of targets without duplicating across every platform.

## expect/actual Usage

- **Use `expect`/`actual` ONLY when no interface+DI solution exists.**
- Prefer interfaces injected via DI (Koin / Kodein) for platform variation — it is testable and composable.
- `expect`/`actual` is appropriate for: platform logging, file system access, crypto/secure storage, biometrics, UUID generation, datetime formatting.
- Every `expect` declaration in `commonMain` must have a matching `actual` in ALL configured platform source sets — missing actuals cause compile errors.
- `actual` implementations may delegate to platform libraries; keep `actual` bodies thin (1-3 lines preferred).

## Networking (Ktor Client)

- Ktor client configured in `commonMain` — platform engines injected per source set.
- `OkHttp` engine for `androidMain`; `Darwin` engine for `iosMain`; `Js` engine for `jsMain`.
- Base URL, timeout, and serialization configured centrally in a `HttpClientFactory` in `commonMain`.
- Use `ContentNegotiation` plugin with `kotlinx.serialization` — not Gson or Jackson (JVM-only).
- Retry and error handling via Ktor's `HttpRequestRetry` plugin or custom response validation.

## Serialization

- `kotlinx.serialization` only in `commonMain` — Gson and Jackson are JVM-only and must not appear in shared code.
- Annotate all serializable types with `@Serializable`.
- Use `@SerialName("snake_case")` to map JSON field names to Kotlin camelCase properties.
- Prefer explicit `@Serializable` data classes over generic `Map<String, Any>` for API responses.
- Custom serializers via `@Serializer(forClass = X::class)` or `KSerializer<T>` — keep them in `commonMain`.

## State Management

- `Flow<T>` for reactive streams in `commonMain` — platform-agnostic and coroutine-native.
- `StateFlow<UiState>` in shared ViewModels or presenters for UI state.
- Android: `collectAsStateWithLifecycle()` in Composables.
- iOS: Bridge `Flow` to Swift `AsyncSequence` via `skie` (SKIE library) or manual `StateFlowWrapper`.
- No `LiveData` in `commonMain` — it is Android-only.
- No `RxJava` in `commonMain` — it is JVM-only.

## Dependency Injection

- **Koin** (preferred) or **Kodein** for cross-platform DI — both support `commonMain` modules.
- **NOT Hilt** — it is JVM/Android-only and cannot be used in `commonMain`.
- Koin modules defined in `commonMain`; platform-specific modules defined in platform source sets.
- `startKoin { modules(appModule, platformModule) }` called in each platform entry point.
- `by inject()` or `get()` for obtaining dependencies in shared ViewModels/use cases.

## Persistence

- **SQLDelight** for cross-platform relational database — generates type-safe Kotlin from SQL.
- `Database` objects defined in `commonMain`; platform drivers (`AndroidSqliteDriver`, `NativeSqliteDriver`) injected per platform.
- **Multiplatform Settings** (russhwolf) for key-value storage (`SharedPreferences` on Android, `NSUserDefaults` on iOS).
- Avoid Room (Android-only) and CoreData (iOS-only) in shared code.

## Concurrency

- Kotlin coroutines with `Dispatchers.Default` and `Dispatchers.IO` in `commonMain`.
- **Never use `Dispatchers.Main` in `commonMain`** — it is platform-specific. Inject `CoroutineDispatcher` for main-thread dispatching.
- `CoroutineScope` tied to platform lifecycle — pass or inject the scope, do not create `GlobalScope` in shared code.
- Kotlin/Native (iOS): coroutines run on a single thread by default; use `Dispatchers.Default` for background work, `.collect { }` on the main dispatcher for UI updates.
- Avoid `@ThreadLocal` and mutable `object` state in `commonMain` — not safe across platforms.

## Naming

| Artifact | Pattern | Notes |
|----------|---------|-------|
| Shared ViewModel / Presenter | `XxxSharedViewModel` | In `commonMain`, no Android-specific inheritance |
| Platform actual class | `actual class PlatformLogger` | In each platform source set |
| Koin module | `val featureModule = module { }` | In `commonMain` or platform source set |
| Ktor API service | `XxxApiService` | In `commonMain/data/remote/` |
| SQLDelight DAO | `XxxQueries` | Auto-generated from `.sq` files |
| Repository interface | `XxxRepository` | In `commonMain`, implemented in `commonMain` or platform |

## Build Configuration

- Gradle plugin: `kotlin("multiplatform")` in `build.gradle.kts`.
- HMPP enabled by default in Kotlin 1.6.20+ — no extra flag needed.
- Configure targets explicitly: `android()`, `iosX64()`, `iosArm64()`, `iosSimulatorArm64()`.
- Use `iosTarget` alias function to apply configuration to all iOS targets at once.
- Keep `commonMain` dependency list lean — every added dependency must compile on all targets.
- Use `api()` vs `implementation()` in source sets deliberately — `api()` exposes to dependents.

## Code Quality

- Functions in `commonMain`: max ~30 lines, prefer ~20 for use case / service methods.
- File size: max ~400 lines, prefer ~200 per class.
- Platform source sets: thin wrappers — business logic belongs in `commonMain`.
- No `TODO("Not implemented")` stubs in `actual` declarations — fail fast with a descriptive exception.

## TDD Flow

```
scaffold -> write tests (RED in commonTest) -> implement in commonMain (GREEN) -> refactor
```

1. **Scaffold**: create interface and `actual` stubs with `TODO("Not yet implemented")`
2. **RED**: write test in `commonTest` expressing expected behaviour — runs on all platforms
3. **GREEN**: implement in `commonMain`; add platform `actual` implementations
4. **Refactor**: clean up, extract, ensure `allTests` still passes on all platforms

## Smart Test Rules

- Test behaviour in `commonTest` — platform-specific behavior tested in platform test source sets.
- Use fakes/stubs over MockK in `commonTest` — MockK may not work on all Kotlin/Native targets.
- `runTest` (from `kotlinx-coroutines-test`) for coroutine tests in `commonTest`.
- Do not test Ktor internals or SQLDelight generated code — test your wrappers and repositories.
- Run `./gradlew allTests` to verify across all configured platforms before shipping.

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: moving platform code to `commonMain` without test coverage, changing public API surface.

## Dos and Don'ts

### Do
- Keep `commonMain` free of JVM-only libraries (Gson, Jackson, Hilt, Room, RxJava)
- Use `kotlinx.serialization` for all serialization needs
- Inject platform dispatchers — never hardcode `Dispatchers.Main` in `commonMain`
- Prefer interfaces + Koin DI over `expect`/`actual` for platform variation
- Define SQL schema in SQLDelight `.sq` files — use generated queries, not raw strings
- Run `./gradlew allTests` to validate all platform targets
- Use SKIE or equivalent to create clean Swift APIs from Kotlin/Coroutines
- Pin Kotlin version and all KMP library versions to the same BOM or matrix entry

### Don't
- Don't import `android.*`, `java.*` (beyond `java.io`/`java.math`), or `Foundation` in `commonMain`
- Don't use `Dispatchers.Main` in `commonMain` — it is platform-specific
- Don't use `expect`/`actual` when a simple interface + DI would suffice
- Don't use Gson or Jackson in shared code — use `kotlinx.serialization`
- Don't use Hilt in `commonMain` — it is JVM/Android-only
- Don't use `GlobalScope` in shared code — tie coroutine scopes to platform lifecycles
- Don't write business logic in platform source sets — keep it in `commonMain`
- Don't ignore `iosTarget` compilation errors by suppressing — fix the `actual` implementation
- Don't use `@ThreadLocal` mutable state in `commonMain` — thread semantics differ per platform
- Don't mix source set concerns — `androidMain` should only contain Android-specific code
