# Jetpack Compose Documentation Conventions

> Support tier: community

> Extends `modules/documentation/conventions.md` with Jetpack Compose-specific patterns.

## Code Documentation

- Use KDoc (`/** */`) for all public `@Composable` functions, `ViewModel` classes, and repository interfaces.
- Composables: document the visual element rendered, non-obvious parameters, and any side effects (launched effects, state hoisting contracts).
- `@Preview` composables: use descriptive names — they are living documentation of design states (loading, error, empty, populated).
- `ViewModel`: document exposed `StateFlow`/`SharedFlow` properties and their lifecycle.
- Repository interfaces: document suspend functions with preconditions, return value semantics, and exception types.

```kotlin
/**
 * Displays an athlete's daily workout card with progress indicators.
 *
 * State hoisting: [onComplete] is called when the user marks the workout done.
 * Caller owns the completion state — this composable is stateless.
 *
 * @param workout The workout to display. Must not be empty.
 * @param onComplete Callback invoked when the user taps "Mark complete".
 */
@Composable
fun WorkoutCard(
    workout: Workout,
    onComplete: (WorkoutId) -> Unit,
    modifier: Modifier = Modifier,
) { ... }
```

## Architecture Documentation

- Document the UI layer architecture: MVVM with `ViewModel` → `StateFlow` → Composable.
- Document the navigation graph: destinations, arguments, and deep link patterns. Use a Mermaid flowchart.
- Document the state hoisting strategy: which components are stateful (hold `ViewModel` reference) vs stateless (receive state as params).
- Hilt dependency injection: document the `@Module` bindings for non-obvious provides.
- Multi-module architecture: document module graph and what each Gradle module owns.

## Diagram Guidance

- **Navigation graph:** Mermaid flowchart showing composable destinations and their arguments.
- **State ownership:** Class diagram showing `ViewModel` → `UiState` → Composable relationships.

## Dos

- KDoc on all public `@Composable` — they form the component library API
- `@Preview` names describing visual states: `WorkoutCard_Loading`, `WorkoutCard_Complete`
- Document `Modifier` parameter conventions: always last, default to `Modifier`

## Don'ts

- Don't document Compose Material3 built-in component behavior — document your project's wrappers
- Don't skip ViewModel `UiState` sealed class documentation — each state variant is an observable contract
