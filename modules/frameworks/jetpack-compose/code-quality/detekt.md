# Jetpack Compose + detekt

> Extends `modules/code-quality/detekt.md` with Jetpack Compose-specific integration.
> Generic detekt conventions are NOT repeated here.

## Integration Setup

Add the `compose-rules` detekt plugin alongside the base detekt setup:

```kotlin
// build.gradle.kts
dependencies {
    detektPlugins("io.gitlab.arturbosch.detekt:detekt-formatting:1.23.7")
    detektPlugins("io.nlopez.compose.rules:detekt:0.4.22")
}
```

Configure Compose-specific rules in `config/detekt.yml`:

```yaml
Compose:
  ComposableNaming:
    active: true
  ComposableFunctionName:
    active: true
    # Composables must be PascalCase
    functionPattern: '[A-Z][a-zA-Z0-9]*'
  CompositionLocalAllowlist:
    active: true
    allowedCompositionLocals: "LocalContentColor,LocalTextStyle"
  ViewModelForwarding:
    active: true   # reject passing ViewModel directly to sub-composables
  MutableStateAutoboxing:
    active: true   # prefer mutableIntStateOf over mutableStateOf<Int>
  RememberMissingKey:
    active: true   # remember(key) not bare remember { }
  UnstableCollections:
    active: true   # prefer ImmutableList/ImmutableMap from kotlinx-collections-immutable
```

Exclude generated Hilt/Dagger code and data binding from detekt source sets:

```kotlin
detekt {
    source.setFrom(
        "src/main/kotlin",
        "src/test/kotlin"
    )
    // Do NOT include build/generated — Hilt and data binding generate there
}
```

## Framework-Specific Patterns

### Composable Naming Convention

Standard Kotlin functions are camelCase; `@Composable` functions that return `Unit` must be PascalCase (treated as UI elements). The `ComposableFunctionName` rule from `compose-rules` enforces this:

```kotlin
// CORRECT
@Composable
fun UserProfileCard(user: User) { ... }

// WRONG — camelCase Composable
@Composable
fun userProfileCard(user: User) { ... }
```

Override the base `naming.FunctionNaming` rule to allow both patterns:

```yaml
naming:
  FunctionNaming:
    functionPattern: '([a-z][a-zA-Z0-9]*|[A-Z][a-zA-Z0-9]*)'
    excludes: ['**/test/**']
```

The `compose-rules` `ComposableFunctionName` rule then enforces PascalCase specifically for `@Composable` Unit functions.

### Preview Function Exclusions

`@Preview` functions are PascalCase by convention but not production composables — suppress complexity rules for them:

```yaml
complexity:
  LongMethod:
    excludes: ['**/*Preview*.kt', '**/ui/preview/**']
style:
  MagicNumber:
    excludes: ['**/test/**', '**/androidTest/**', '**/*Preview*.kt']
```

### ViewModel Forwarding Guard

`ViewModelForwarding` prevents passing a ViewModel instance into child composables — enforce state hoisting:

```kotlin
// WRONG — ViewModel leaks into composable graph
@Composable
fun OrderScreen(viewModel: OrderViewModel) {
    OrderList(viewModel = viewModel)  // detekt: ViewModelForwarding
}

// CORRECT — hoist state, pass only data + callbacks
@Composable
fun OrderScreen(viewModel: OrderViewModel) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    OrderList(orders = state.orders, onOrderClick = viewModel::onOrderClick)
}
```

## Additional Dos

- Enable `UnstableCollections` — passing `List<T>` to composables skips recomposition stability; use `ImmutableList`.
- Enable `RememberMissingKey` — `remember { expensiveComputation(input) }` without `input` as a key causes stale values.
- Run `detektMain` (with type resolution) in CI — compose-rules rules require type resolution to detect ViewModel forwarding.
- Separate test detekt config: allow `MagicNumber` in `androidTest/` (instrumented tests use pixel values).

## Additional Don'ts

- Don't suppress `ComposableFunctionName` globally — it exists specifically to enforce the PascalCase Compose contract.
- Don't include `build/generated/` in detekt source: Hilt-generated `*_HiltModules.kt` files have intentional style violations.
- Don't disable `ViewModelForwarding` — it flags a real architecture problem, not a style preference.
- Don't set `allRules = true` with compose-rules plugin present — several experimental Compose rules produce noise on established codebases.
