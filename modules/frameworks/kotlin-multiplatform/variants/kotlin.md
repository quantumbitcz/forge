# Kotlin Multiplatform + Kotlin Variant

> Extends `modules/frameworks/kotlin-multiplatform/conventions.md` with KMP-specific Kotlin patterns.
> General Kotlin idioms are in `modules/languages/kotlin.md` — not duplicated here.

## expect/actual Conventions

```kotlin
// commonMain
expect class PlatformLogger(tag: String) {
    fun log(message: String)
}

// androidMain
actual class PlatformLogger actual constructor(private val tag: String) {
    actual fun log(message: String) = android.util.Log.d(tag, message)
}

// iosMain
actual class PlatformLogger actual constructor(private val tag: String) {
    actual fun log(message: String) = println("[$tag] $message")
}
```

- `actual` constructor must mirror `expect` constructor signature exactly.
- Use `actual typealias` when a platform type directly satisfies the `expect` interface.
- Never put business logic in `expect` declarations — only the contract, not the implementation.
- Use `@Deprecated` on `expect` before removing — gives platform maintainers time to update `actual`.

## Source Set Boundary Types

| Source Set | Allowed Imports | Forbidden |
|------------|-----------------|-----------|
| `commonMain` | `kotlin.*`, `kotlinx.*`, `io.ktor.*`, `com.squareup.sqldelight.*` | `android.*`, `java.util.*` (except UUID via extension), `Foundation` |
| `androidMain` | All `commonMain` + `android.*`, `java.*` | iOS/Darwin frameworks |
| `iosMain` | All `commonMain` + `platform.Foundation.*`, `platform.darwin.*` | Android SDK |
| `jsMain` | All `commonMain` + `kotlinx.browser.*`, `org.w3c.*` | Native/Android SDKs |

## Kotlin Flow in commonMain

```kotlin
// Repository in commonMain
interface XxxRepository {
    fun observeItems(): Flow<List<XxxItem>>
    suspend fun getItem(id: String): XxxItem?
}

// Shared ViewModel / Presenter
class XxxSharedViewModel(private val repository: XxxRepository) {
    private val _state = MutableStateFlow(XxxUiState())
    val state: StateFlow<XxxUiState> = _state.asStateFlow()

    fun loadItems() {
        // Platform-injected scope; not directly owned here
    }
}
```

- Expose `StateFlow` for observable state and `Flow` for streams — both compile on all targets.
- Suspend functions for single-shot operations (`suspend fun fetch(): Result<T>`).

## Coroutine Scope Pattern

```kotlin
// commonMain interface
interface AppCoroutineScope {
    val scope: CoroutineScope
}

// androidMain actual
class AndroidAppCoroutineScope : AppCoroutineScope {
    override val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
}

// iosMain actual
class IosAppCoroutineScope : AppCoroutineScope {
    override val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
}
```

- Never call `runBlocking` in `commonMain` — it blocks the calling thread which may be the UI thread on iOS.
- Pass `CoroutineDispatcher` as a constructor parameter for testability.

## Koin Module Pattern

```kotlin
// commonMain
val networkModule = module {
    single { HttpClientFactory.create(get()) }
    single<XxxApiService> { XxxApiServiceImpl(get()) }
}

val repositoryModule = module {
    single<XxxRepository> { XxxRepositoryImpl(get(), get()) }
}

// androidMain
val androidPlatformModule = module {
    single<PlatformLogger> { PlatformLogger("App") }
    single { AndroidAppCoroutineScope() as AppCoroutineScope }
}
```

## Immutable Collections in commonMain

- `List<T>`, `Map<K, V>`, `Set<T>` from Kotlin stdlib are stable across platforms.
- `kotlinx.collections.immutable` (`ImmutableList`, `PersistentMap`) for guaranteed immutability — useful with Compose on Android.
- Avoid Java collections (`java.util.ArrayList`, `java.util.HashMap`) in `commonMain`.

## Kotlin Serialization in KMP

```kotlin
@Serializable
data class XxxDto(
    @SerialName("item_id") val itemId: String,
    @SerialName("created_at") val createdAt: String,
    val name: String
)
```

- All network response/request types must be `@Serializable`.
- Use `Json { ignoreUnknownKeys = true }` in `HttpClientFactory` for resilience to API changes.
- Custom serializers extend `KSerializer<T>` in `commonMain` — no platform-specific dependencies.

## Swift Interop Considerations (iosMain)

- Keep `actual` classes simple — Swift sees them as Objective-C compatible types.
- Avoid generic `actual` classes where possible — generics map awkwardly to Swift.
- Use SKIE to generate idiomatic Swift wrappers for `Flow`, `StateFlow`, and suspend functions.
- Kotlin `sealed class` in `commonMain` maps to a Swift enum-like pattern via SKIE.
- Prefix `actual` iOS classes with platform-neutral names (not `NS` or `UI`) to avoid confusion.
