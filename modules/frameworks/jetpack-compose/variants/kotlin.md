# Jetpack Compose + Kotlin Variant

> Extends `modules/frameworks/jetpack-compose/conventions.md` with Kotlin-specific Compose patterns.
> General Kotlin idioms are in `modules/languages/kotlin.md` — not duplicated here.

## Compose Compiler and Kotlin Version Alignment

- Compose compiler version must match the Kotlin version exactly — mismatches cause build failures.
- Use `composeOptions { kotlinCompilerExtensionVersion }` in `build.gradle.kts`; prefer the Compose BOM to manage all Compose library versions together.
- Enable `@OptIn(ExperimentalMaterial3Api::class)` at the site of use — not globally in the module.

## State Hoisting with Kotlin

- ViewModel state is `private val _uiState = MutableStateFlow(XxxUiState())` exposed as `val uiState: StateFlow<XxxUiState> = _uiState.asStateFlow()`.
- Use Kotlin data class `copy()` to emit state updates: `_uiState.update { it.copy(isLoading = true) }`.
- For `UiEvent` (one-shot): `private val _events = Channel<XxxUiEvent>(Channel.BUFFERED)` exposed as `val events = _events.receiveAsFlow()`.

## Kotlin-Specific Compose APIs

- `remember { mutableStateOf(...) }` can be written as `remember { mutableStateOf(value) }` or delegated: `var expanded by remember { mutableStateOf(false) }`.
- Prefer delegation syntax (`by`) over destructuring (`val (state, setState) = remember { mutableStateOf(false) }`) for readability.
- `derivedStateOf` with Kotlin lambda: `val isEnabled by remember { derivedStateOf { items.isNotEmpty() && !isLoading } }`.
- Kotlin's `@Composable` functions are inline-like — avoid capturing mutable variables from outer scope.

## Coroutines in ViewModel

- `viewModelScope.launch { }` for fire-and-forget operations in ViewModel.
- `viewModelScope.launch(Dispatchers.IO) { }` for I/O; results collected via `flow` operators, never blocking `runBlocking`.
- Use `stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), initialValue)` to convert cold `Flow` to `StateFlow` for UI.
- Handle errors with `catch { }` in flows or `try/catch` in launch blocks — always update `UiState.error`.

## Sealed Classes for UI State

```kotlin
data class XxxUiState(
    val items: List<XxxItem> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null
)

sealed class XxxUiEvent {
    data class ShowSnackbar(val message: String) : XxxUiEvent()
    data object NavigateBack : XxxUiEvent()
}
```

- `UiState` is a data class (not sealed) — it represents a continuous state with optional fields.
- `UiEvent` is sealed — it represents discrete one-shot events that are consumed once.

## Kotlin Serialization for Navigation Routes

```kotlin
@Serializable
data class DetailRoute(val itemId: String)

@Serializable
data object HomeRoute
```

- Use `@Serializable` on route data classes/objects — avoids string-based navigation arguments.
- Primitive types only in route parameters — no complex objects (they don't survive process death).

## Extension Functions for Compose

- Group Compose-specific extensions in `*Extensions.kt` or `*Composables.kt` files.
- Modifier extension functions for reusable decoration patterns: `fun Modifier.cardShadow() = this.shadow(...)`.
- Use `@Composable` extension functions on theme objects sparingly — prefer stateless utility composables.

## Immutability Annotations

- `@Immutable` on data classes with only immutable properties — enables strong skipping optimization.
- `@Stable` on classes with mutable properties that notify Compose of changes (e.g., `SnapshotStateList`).
- `List<T>` is considered unstable by Compose — wrap in `@Immutable` data class or use `kotlinx.collections.immutable.ImmutableList`.

## Null Safety in Compose

- Prefer `UiState.content: ContentState?` over nullable top-level state — makes loading/error/success explicit.
- Use `?.let { }` in composables for conditional rendering: `uiState.error?.let { ErrorBanner(message = it) }`.
- Avoid `!!` in composables — treat null as an empty/error state branch.
