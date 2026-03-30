# Jetpack Compose + Dokka

> Extends `modules/code-quality/dokka.md` with Jetpack Compose-specific integration.
> Generic Dokka conventions are NOT repeated here.

## Integration Setup

```kotlin
// build.gradle.kts
plugins {
    id("org.jetbrains.dokka") version "1.9.20"
}

tasks.dokkaHtml {
    outputDirectory.set(layout.buildDirectory.dir("dokka"))
    dokkaSourceSets {
        named("main") {
            moduleName.set("YourApp")
            // Link source to GitHub for navigation
            sourceLink {
                localDirectory.set(file("src/main/kotlin"))
                remoteUrl.set(uri("https://github.com/org/app/blob/main/src/main/kotlin").toURL())
                remoteLineSuffix.set("#L")
            }
            // Suppress Hilt and generated internal packages
            perPackageOption {
                matchingRegex.set(".*\\.di\\..*")
                suppress.set(true)
            }
            perPackageOption {
                matchingRegex.set(".*\\.generated\\..*")
                suppress.set(true)
            }
        }
    }
}
```

## Framework-Specific Patterns

### Documenting Composable Previews

Use KDoc on `@Preview`-annotated functions to document the visual scenario being demonstrated:

```kotlin
/**
 * Preview of [UserProfileCard] in loaded state with a full user profile.
 *
 * Demonstrates: avatar display, badge rendering, action button layout.
 */
@Preview(showBackground = true, name = "Profile — loaded")
@Composable
private fun UserProfileCardPreview() {
    AppTheme {
        UserProfileCard(user = PreviewData.fullUser)
    }
}
```

Mark preview functions with `@suppress` if you want them excluded from the public API docs:

```kotlin
/** @suppress Preview only. */
@Preview
@Composable
private fun ButtonLoadingPreview() { ... }
```

### Documenting Composable Parameters

Document `modifier` as the last positional parameter per Compose convention; document state parameters, event callbacks, and UX constraints:

```kotlin
/**
 * Displays a card with the user's profile information.
 *
 * @param user The user data to display. Pass `null` to show a loading skeleton.
 * @param onEditClick Callback invoked when the edit button is tapped.
 * @param modifier Modifier applied to the card's root layout.
 */
@Composable
fun UserProfileCard(
    user: User?,
    onEditClick: () -> Unit,
    modifier: Modifier = Modifier,
)
```

### Documenting UiState Sealed Classes

Document the sealed class and each subtype — these are the primary API contract between ViewModel and UI:

```kotlin
/**
 * UI state for the order list screen.
 *
 * The screen renders differently for each state — see [Loading], [Success], [Error].
 */
sealed interface OrderListUiState {
    /** Initial loading state — show full-screen skeleton. */
    data object Loading : OrderListUiState

    /**
     * Orders loaded successfully.
     * @property orders Non-empty list of orders to display.
     */
    data class Success(val orders: List<Order>) : OrderListUiState

    /**
     * Failed to load orders.
     * @property message User-facing error message.
     * @property retryable Whether the user can retry the load.
     */
    data class Error(val message: String, val retryable: Boolean) : OrderListUiState
}
```

## Additional Dos

- Document every `@Composable` public function with at least a one-line KDoc summary.
- Use `@param modifier` documentation on every composable that accepts a `Modifier` — its position and default value are part of the public contract.
- Suppress internal `di/`, `generated/`, and Hilt component packages to keep the API doc surface clean.
- Use `@sample` tags on reusable component docs to link to preview functions as living examples.

## Additional Don'ts

- Don't document `@HiltViewModel` ViewModels' Hilt constructor (`@Inject constructor`) in the public API — document the public methods and state flows only.
- Don't use raw HTML in KDoc on composables — it renders inconsistently in Android Studio's Quick Doc popup.
- Don't suppress public composable functions to skip documentation — if it's public, document it.
- Don't run `dokkaHtmlMultiModule` in standard CI on every push for a single-module Android app — gate it on the release branch.
