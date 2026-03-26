# Jetpack Compose + JUnit 5 Testing

> Extends `modules/testing/junit5.md` with Compose-specific UI and ViewModel testing patterns.
> Generic JUnit 5 conventions (nested classes, AssertJ, Mockito, parameterized tests) are NOT repeated here.

## Compose Test Rules

### Unit / Composable Tests (no Activity)
```kotlin
@get:Rule
val composeTestRule = createComposeRule()

@Test
fun `login button is disabled when fields are empty`() {
    composeTestRule.setContent {
        LoginContent(email = "", password = "", onLogin = {}, isLoading = false)
    }
    composeTestRule.onNodeWithTag("login_button").assertIsNotEnabled()
}
```

### Instrumented Tests (with Activity)
```kotlin
@get:Rule
val composeTestRule = createAndroidComposeRule<MainActivity>()

@Test
fun `navigates to home after successful login`() {
    composeTestRule.onNodeWithTag("email_field").performTextInput("user@example.com")
    composeTestRule.onNodeWithTag("password_field").performTextInput("password123")
    composeTestRule.onNodeWithTag("login_button").performClick()
    composeTestRule.onNodeWithTag("home_screen").assertIsDisplayed()
}
```

## Semantics-Based Assertions

- `onNodeWithTag("tag")` — preferred for stability across localization and text changes.
- `onNodeWithText("text")` — use only when testing that specific text is displayed.
- `onNodeWithContentDescription("desc")` — for accessibility-labeled elements.
- `assertIsDisplayed()` — element is visible on screen.
- `assertIsNotDisplayed()` — element exists in tree but not visible.
- `assertDoesNotExist()` — element not in composition tree at all.
- `assertIsEnabled()` / `assertIsNotEnabled()` — for interactive elements.

## Interaction

```kotlin
// Click
composeTestRule.onNodeWithTag("submit_button").performClick()

// Text input
composeTestRule.onNodeWithTag("search_field").performTextInput("kotlin")

// Scroll
composeTestRule.onNodeWithTag("items_list").performScrollToIndex(10)

// Combined actions
composeTestRule.onNodeWithTag("text_field")
    .performTextClearance()
    .performTextInput("new value")
```

## ViewModel Unit Testing

```kotlin
@ExtendWith(MockitoExtension::class)
class XxxViewModelTest {
    @Mock lateinit var repository: XxxRepository

    private lateinit var viewModel: XxxViewModel

    @BeforeEach
    fun setup() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        viewModel = XxxViewModel(repository)
    }

    @AfterEach
    fun teardown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `loading state emitted before data arrives`() = runTest {
        whenever(repository.getItems()).thenReturn(flowOf(emptyList()))
        val states = mutableListOf<XxxUiState>()
        val job = launch { viewModel.uiState.toList(states) }
        advanceUntilIdle()
        assertThat(states).anyMatch { it.isLoading }
        job.cancel()
    }
}
```

- Always set `Dispatchers.Main` via `UnconfinedTestDispatcher` or `StandardTestDispatcher` in `@BeforeEach`.
- `runTest` for coroutine-aware tests — replaces `runBlocking` in test context.
- `advanceUntilIdle()` to drain coroutine queues when using `StandardTestDispatcher`.

## Robolectric for Unit Tests Without Emulator

```kotlin
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class XxxScreenTest {
    @get:Rule val composeTestRule = createComposeRule()

    @Test
    fun `error banner is shown when error state set`() {
        composeTestRule.setContent {
            XxxScreen(uiState = XxxUiState(error = "Network error"), onRetry = {})
        }
        composeTestRule.onNodeWithTag("error_banner").assertIsDisplayed()
    }
}
```

- Robolectric enables Compose UI tests on JVM without an Android emulator (fast CI).
- Use `@Config(sdk = [33])` to target a specific Android SDK version.
- Not suitable for tests that require real hardware sensors, camera, or Bluetooth.

## Screenshot Testing with Paparazzi

```kotlin
@RunWith(JUnit4::class)
class XxxScreenshotTest {
    @get:Rule val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_6)

    @Test
    fun `home screen light theme`() {
        paparazzi.snapshot {
            AppTheme(darkTheme = false) {
                HomeContent(uiState = HomeUiState(items = fakeItems))
            }
        }
    }

    @Test
    fun `home screen dark theme`() {
        paparazzi.snapshot {
            AppTheme(darkTheme = true) {
                HomeContent(uiState = HomeUiState(items = fakeItems))
            }
        }
    }
}
```

- Screenshot tests catch unintended visual regressions without running on a device.
- Always test both light and dark themes for every screen.
- Store golden images in VCS; update with `./gradlew recordPaparazziDebug` when changes are intentional.
- Do not use Paparazzi to test interaction — it is for visual regression only.

## What to Test at Each Layer

| Layer | Test type | Tools |
|-------|-----------|-------|
| Screen (stateless content composable) | Compose UI test | `createComposeRule()`, Robolectric |
| Screen (with ViewModel) | Instrumented / Robolectric | `createAndroidComposeRule<Activity>()` |
| ViewModel | Unit | JUnit 5, Mockito, `UnconfinedTestDispatcher` |
| Repository | Unit / Integration | Mockito for data sources; in-memory DB for integration (depends on `persistence:`) |
| Visual regression | Screenshot | Paparazzi |
