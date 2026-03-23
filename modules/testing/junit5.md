# JUnit 5 Testing Conventions

## Test Structure

Organize with `@Nested` classes to group related scenarios. One top-level test class per production class. Use `@DisplayName` for human-readable descriptions at both class and method level.

```java
@DisplayName("OrderService")
class OrderServiceTest {

    @Nested
    @DisplayName("when placing an order")
    class PlaceOrder {
        @Test
        @DisplayName("should persist and return the saved order")
        void persistsAndReturns() { ... }
    }
}
```

## Naming

- Test class: `{Subject}Test`
- Method: `{action}_{context}__{expectation}` or plain English with `@DisplayName`
- Prefer `@DisplayName` over encoding context into the method name

## Assertions / Matchers

Prefer AssertJ over JUnit's built-in `assertEquals`:

```java
assertThat(result).isEqualTo(expected);
assertThat(list).containsExactly(a, b, c);
assertThat(map).containsEntry("key", "value");
assertThat(str).startsWith("prefix").endsWith("suffix");
assertThat(optional).isPresent().hasValue(item);
```

For exceptions:

```kotlin
assertThrows<NotFoundException> { service.find(unknownId) }
    .message shouldContain "not found"
```

## Lifecycle

```java
@BeforeAll  static void globalSetup()    { /* once per class, must be static */ }
@AfterAll   static void globalTeardown() { }
@BeforeEach void setUp()    { /* before each @Test */ }
@AfterEach  void tearDown() { /* after each @Test  */ }
```

Use `@TestInstance(Lifecycle.PER_CLASS)` when you need non-static `@BeforeAll`.

## Mocking

Prefer Mockito via `@ExtendWith(MockitoExtension.class)`:

```java
@Mock UserRepository repo;
@InjectMocks UserService service;

when(repo.findById(id)).thenReturn(Optional.of(user));
verify(repo).save(any(User.class));
verifyNoMoreInteractions(repo);
```

In Kotlin tests use MockK instead of Mockito for suspend function support.

## Data-Driven Testing

```java
@ParameterizedTest
@ValueSource(strings = {"alice", "bob", "charlie"})
void acceptsValidNames(String name) { ... }

@ParameterizedTest
@CsvSource({"1, ONE", "2, TWO", "3, THREE"})
void mapsNumberToWord(int num, String word) { ... }

@ParameterizedTest
@MethodSource("provideOrders")
void handlesEdgeCases(Order order, boolean expected) { ... }

static Stream<Arguments> provideOrders() {
    return Stream.of(Arguments.of(emptyOrder, false), ...);
}
```

## Async Testing

For `CompletableFuture`: call `.get()` with a timeout inside the test.
For reactive (Reactor): use `StepVerifier`:

```java
StepVerifier.create(mono)
    .expectNext(expected)
    .verifyComplete();
```

For Kotlin coroutines: use `runTest {}` from `kotlinx-coroutines-test`.

## What NOT to Test

- Auto-generated getters/setters with no logic
- Framework bootstrap (Spring context loading) in unit tests — use `@SpringBootTest` slices sparingly
- Serialization format of third-party DTOs you don't own
- Transitive dependencies of your unit under test

## Anti-Patterns

- `Thread.sleep()` for async coordination — use `awaitility` or `StepVerifier`
- Mocking the class under test itself
- Asserting on `toString()` output for equality
- More than one logical assertion concept per `@Test` without `assertSoftly`
- `@Disabled` without a linked ticket or expiry comment
