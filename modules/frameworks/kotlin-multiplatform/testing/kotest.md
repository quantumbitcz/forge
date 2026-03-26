# Kotlin Multiplatform + Kotest Testing

> Extends `modules/testing/kotest.md` with KMP-specific cross-platform testing patterns.
> Generic Kotest conventions (ShouldSpec, matchers, data-driven tests) are NOT repeated here.

## commonTest: Cross-Platform Tests

All tests in `commonTest` run on every configured target. Write the majority of shared logic tests here.

```kotlin
// commonTest/kotlin/com/example/XxxRepositoryTest.kt
class XxxRepositoryTest : ShouldSpec({
    val fakeDataSource = FakeXxxDataSource()
    val repository = XxxRepositoryImpl(fakeDataSource)

    should("return items from data source") {
        fakeDataSource.items = listOf(fakeItem("1"), fakeItem("2"))
        val result = repository.getItems()
        result shouldHaveSize 2
    }
})
```

- `commonTest` has no access to MockK on Kotlin/Native — use hand-written fakes and stubs instead.
- Fakes defined in `commonTest/kotlin/fakes/` are shared across all platform test source sets.
- Avoid `@JvmStatic`, `@JvmOverloads`, and other JVM annotations in `commonTest`.

## runTest for Coroutines

```kotlin
// commonTest
class XxxViewModelTest : ShouldSpec({
    should("emit loading state then content") {
        runTest {
            val repository = FakeXxxRepository()
            val viewModel = XxxSharedViewModel(repository, this)
            val states = mutableListOf<XxxUiState>()
            val job = launch { viewModel.state.toList(states) }
            advanceUntilIdle()
            states.first().isLoading shouldBe true
            states.last().items shouldNotBeEmpty
            job.cancel()
        }
    }
})
```

- `runTest` from `kotlinx-coroutines-test` works in `commonTest` on all platforms.
- `advanceUntilIdle()` for `StandardTestDispatcher`; no advance needed with `UnconfinedTestDispatcher`.
- Pass `TestCoroutineScope` or `TestDispatcher` into shared classes for controllable test execution.

## Platform-Specific Test Source Sets

Use platform test source sets only for tests that require platform APIs or test `actual` implementations:

```kotlin
// androidUnitTest
class AndroidPlatformLoggerTest : ShouldSpec({
    should("log to Android logcat") {
        val logger = PlatformLogger("TestTag")
        // Android-specific assertion
        logger.log("test message") // verify via Robolectric shadow
    }
})

// iosTest (run on iOS simulator / device)
class IosPlatformLoggerTest {
    @Test
    fun testLog() {
        val logger = PlatformLogger("TestTag")
        logger.log("test message") // verify iOS NSLog output
    }
}
```

## Fakes Over Mocks in commonTest

```kotlin
// commonTest/kotlin/fakes/FakeXxxRepository.kt
class FakeXxxRepository : XxxRepository {
    var items: List<XxxItem> = emptyList()
    var shouldThrow: Boolean = false

    override fun observeItems(): Flow<List<XxxItem>> = flowOf(items)

    override suspend fun getItem(id: String): XxxItem? {
        if (shouldThrow) throw RuntimeException("Simulated error")
        return items.find { it.id == id }
    }
}
```

- Fakes are simpler than mocks and work reliably across all Kotlin targets.
- Store fakes in a dedicated `fakes/` package in `commonTest` — reuse across test classes.
- Fake state is set before the test and asserted after — no mock verification syntax needed.

## Running All Platform Tests

```bash
# Run all tests on all configured platforms
./gradlew allTests

# Run only common (JVM) tests
./gradlew :shared:jvmTest

# Run Android unit tests
./gradlew :shared:testDebugUnitTest

# Run iOS tests (requires macOS + Xcode)
./gradlew :shared:iosSimulatorArm64Test
```

- `allTests` is the CI gate command — it runs all platform tests in sequence.
- iOS tests require macOS with Xcode installed; skip with `--exclude-task iosTest` on non-Mac CI.
- Use `XCTest` or Kotest on iOS targets — both compile to `XCTestCase` for Xcode execution.

## What to Test at Each Layer

| Layer | Test location | Tools |
|-------|--------------|-------|
| Use cases / domain logic | `commonTest` | Kotest ShouldSpec, fakes, `runTest` |
| Repository (shared) | `commonTest` | Kotest, fake data sources |
| `actual` implementations | Platform test source sets | Platform-specific test tools |
| Persistence queries | `commonTest` + in-memory driver | In-memory drivers per platform (depends on `persistence:` choice) |
| Ktor API client | `commonTest` | `MockEngine` from `ktor-client-mock` |
| Full platform integration | Android instrumented / iOS XCTest | Espresso / XCUITest |

## Ktor MockEngine in commonTest

```kotlin
// commonTest
class XxxApiServiceTest : ShouldSpec({
    val mockEngine = MockEngine { request ->
        respond(
            content = ByteReadChannel("""[{"item_id":"1","name":"Test"}]"""),
            status = HttpStatusCode.OK,
            headers = headersOf(HttpHeaders.ContentType, "application/json")
        )
    }
    val client = HttpClient(mockEngine) {
        install(ContentNegotiation) { json() }
    }
    val service = XxxApiServiceImpl(client)

    should("parse items from API response") {
        val items = service.getItems()
        items shouldHaveSize 1
        items.first().name shouldBe "Test"
    }
})
```

- `ktor-client-mock` works in `commonTest` — it is a multiplatform library.
- Test happy paths and error paths (4xx, 5xx, network errors) using `MockEngine`.
