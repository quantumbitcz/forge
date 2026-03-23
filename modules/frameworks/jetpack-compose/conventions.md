# Jetpack Compose Framework Conventions

> Language-agnostic Compose patterns. Language-specific Kotlin idioms are in `modules/languages/kotlin.md`.
> Framework-language integration is in `variants/kotlin.md`.

## Architecture (MVVM + Unidirectional Data Flow)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `ui/` | Composables, screens, components | ViewModel only (via `hiltViewModel()`) |
| `viewmodel/` | UI state, event handling, business logic orchestration | Repositories, UseCases |
| `repository/` | Data access abstraction, caching strategy | DataSources |
| `datasource/` | Network, database, local storage | Retrofit, Room, DataStore |

**Dependency rule:** Composables never call repositories or data sources directly — always via ViewModel.
UI layer emits events upward; state flows down. No bidirectional data binding.

## Composables

- **Stateless by default:** Composables receive state and callbacks as parameters, do not own state.
- Hoist all meaningful state to the ViewModel — only ephemeral UI state (focus, expand/collapse) belongs in `remember`.
- Use `rememberSaveable` when local state must survive configuration changes (e.g., text field value before submission).
- Composables are pure functions of their inputs — no side effects during composition.
- Split large screens into smaller composable functions; prefer one responsibility per composable.
- `@Preview` annotations required for all leaf UI components; use `@PreviewParameter` for data-driven previews.

## State Management

- ViewModel exposes `StateFlow<UiState>` — never `LiveData` in new code.
- Collect in Composable: `val uiState by viewModel.uiState.collectAsStateWithLifecycle()`.
- `mutableStateOf` is only allowed inside ViewModel (for local ViewModel state) — not directly in `@Composable` functions.
- Model UI state as a sealed class: `data class UiState(val content: Content?, val isLoading: Boolean, val error: String?)`.
- Prefer a single top-level `UiState` per screen over many scattered `StateFlow` instances.

## Navigation

- Navigation Compose with type-safe routes via Kotlin serialization (`@Serializable` data objects/classes).
- All routes defined in a sealed interface `AppRoute`; no string literals for navigation destinations.
- `NavHost` defined at app level; screens receive `NavController` or navigate via callbacks, never directly.
- Deep links declared in `NavDeepLink` inside the `composable {}` builder.
- Pass minimal navigation arguments — load full data inside destination ViewModel from repository.

## Dependency Injection (Hilt)

- `@HiltViewModel` on every ViewModel — never instantiate ViewModels manually.
- `hiltViewModel()` in Composable (not `viewModel()`) to leverage Hilt's scoping.
- Dependencies declared via `@Inject constructor` — no field injection.
- Modules declared with `@Module` + `@InstallIn` (component scope appropriate to lifecycle).
- `@Singleton` for app-scoped dependencies (repositories, network clients); `@ViewModelScoped` for ViewModel-scoped.

## Theming (Material 3)

- All colors via `MaterialTheme.colorScheme.*` tokens — never hardcoded hex values.
- All typography via `MaterialTheme.typography.*` tokens — never hardcoded `sp` values directly.
- Custom design tokens defined in a `AppTheme` wrapper composable with light/dark `ColorScheme` variants.
- Dark theme support required: use `isSystemInDarkTheme()` to switch color schemes.
- Dynamic color (Material You) enabled where appropriate via `dynamicColorScheme()`.

## Side Effects

- `LaunchedEffect(key)` for coroutines tied to a composable's lifecycle — key changes restart the effect.
- `DisposableEffect(key)` for effects that require cleanup (listeners, subscriptions).
- `rememberCoroutineScope()` for user-triggered coroutines (button click → launch).
- `SideEffect` for synchronizing non-Compose state after each successful composition.
- Never launch coroutines or call `suspend` functions directly during composition — use effect handlers.

## Lists

- `LazyColumn` / `LazyRow` for all scrollable lists — never `Column` / `Row` with `forEach` for more than 3 static items.
- Always provide a stable `key` parameter: `items(items, key = { it.id })`.
- `LazyVerticalGrid` / `LazyHorizontalGrid` for grid layouts.
- Avoid creating objects inside `items {}` lambda — derive stable keys outside.

## Error Handling

- ViewModel exposes error state as part of `UiState` — not via `SharedFlow` / `Channel` for persistent errors.
- Use `SharedFlow` / `Channel` for one-shot events (navigation, snackbars) that must not be re-displayed on recomposition.
- Sealed result type in ViewModel: `Result<T>` or custom `sealed class Outcome<T>`.
- Composable renders error UI branch from `UiState.error` — never swallows errors silently.

## Performance

- `derivedStateOf { }` for computed values derived from other state — prevents unnecessary recompositions.
- `remember(key) { computation }` for expensive computations — key invalidates cache on change.
- Mark stable data classes with `@Stable` or `@Immutable` to enable Compose compiler optimizations.
- Avoid unstable lambda captures in composables — hoist lambdas or use `rememberUpdatedState`.
- Profile with `Layout Inspector` / Compose metrics before optimizing — measure first.
- `Modifier` parameters should be passed through to root composable to allow caller customization.

## Accessibility

- `contentDescription` required on all `Image` and icon-only `IconButton` composables.
- Use `semantics { }` modifier for custom accessibility actions and roles.
- `testTag("tag_name")` on interactive elements and key UI nodes for UI testing.
- Minimum touch target size: 48dp × 48dp (use `Modifier.minimumInteractiveComponentSize()`).
- Do not convey information via color alone — pair with text or icons.

## Naming

| Artifact | Pattern | Notes |
|----------|---------|-------|
| Screen composable | `XxxScreen` | Top-level screen composable accepting ViewModel |
| Content composable | `XxxContent` | Stateless composable for `XxxScreen` content |
| ViewModel | `XxxViewModel` | `@HiltViewModel`, one per screen |
| UI state | `XxxUiState` | Sealed class or data class |
| UI event | `XxxUiEvent` | Sealed class for one-shot events |
| Route | `XxxRoute` | `@Serializable` data object / class |

## Code Quality

- Composable functions: max ~40 lines; extract sub-composables when exceeded.
- ViewModel methods: max ~30 lines.
- File size: max ~400 lines, prefer ~200 per composable file.
- No business logic in Composables — delegate to ViewModel.
- No `System.out.println` / `print` — use `Timber` or `android.util.Log` sparingly in debug builds only.

## TDD Flow

```
scaffold -> write tests (RED) -> implement (GREEN) -> refactor
```

1. **Scaffold**: create screen stub, ViewModel stub with empty `UiState`, navigation route
2. **RED**: write Compose UI test expressing expected behaviour — must fail
3. **GREEN**: implement minimum composable + ViewModel logic to pass
4. **Refactor**: extract composables, apply performance annotations — tests must still pass

## Smart Test Rules

- Test user-visible behavior via semantics — not internal composable structure.
- `onNodeWithTag()` preferred over `onNodeWithText()` for stability across localization.
- ViewModel unit tests are pure Kotlin — no Android framework dependencies.
- One logical scenario per test; use `@TestParameter` / parameterized rules for variants.
- Screenshot tests (Paparazzi) complement — do not replace — behavior tests.
- Do not test recomposition internals or Compose framework mechanics.

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated screens, changing navigation contracts, fixing pre-existing crashes.

## Dos and Don'ts

### Do
- Keep Composables stateless — hoist all meaningful state to ViewModel
- Use `collectAsStateWithLifecycle()` to collect `StateFlow` (lifecycle-aware, cancels on stop)
- Use type-safe navigation routes (`@Serializable` data objects/classes)
- Annotate stable data classes with `@Stable` / `@Immutable` for recomposition optimization
- Use `LazyColumn`/`LazyRow` with stable `key` for all scrollable lists
- Provide `contentDescription` on all visual-only elements
- Use `derivedStateOf` for values computed from other state
- Use `@HiltViewModel` and `hiltViewModel()` exclusively for ViewModel injection
- Apply `testTag` to interactive UI nodes for reliable test targeting
- Use Material 3 color scheme tokens — never hardcoded hex

### Don't
- Don't use `LiveData` in new ViewModels — use `StateFlow`
- Don't call `collectAsState()` without lifecycle awareness — always use `collectAsStateWithLifecycle()`
- Don't put side effects (coroutine launches, subscriptions) directly in composition — use `LaunchedEffect`/`DisposableEffect`
- Don't use `Column` with `forEach` for scrollable lists — use `LazyColumn`
- Don't put `mutableStateOf` in `@Composable` function bodies (only in `remember` for local UI state)
- Don't navigate via `NavController` passed deep into a composable hierarchy — use callbacks
- Don't skip `key` parameter in `LazyColumn` items
- Don't hardcode colors, font sizes, or dimensions — use theme tokens and `dp`/`sp` constants
- Don't ignore recomposition performance — profile before shipping
- Don't write business logic in Composables — all logic belongs in ViewModel or below
