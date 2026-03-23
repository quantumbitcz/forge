# Kotest Testing Conventions

## Test Structure

Use `ShouldSpec` as the default spec style. Group related tests inside `context()` blocks when behaviour varies by state or input category. One spec class per production class.

```kotlin
class UserServiceTest : ShouldSpec({
    context("when user exists") {
        should("return the user") { ... }
    }
    context("when user does not exist") {
        should("throw NotFoundException") { ... }
    }
})
```

## Naming

- Outer context: describes the subject or state — `"when the cart is empty"`, `"given a valid token"`
- `should` block: describes the expected outcome — `"should return an empty list"`, `"should throw AuthException"`
- Avoid implementation names like `"test createUser calls repository"` — name the behaviour, not the mechanism

## Assertions / Matchers

Prefer Kotest matchers over `assertEquals`:

```kotlin
result shouldBe expected
list shouldContain item
str shouldStartWith "prefix"
obj shouldBeInstanceOf<Admin>()
value shouldBeNull()
value shouldNotBeNull()
{ dangerousOp() }.shouldThrow<IllegalStateException>()
```

Use `shouldThrow<T> {}` for expected exceptions — captures and returns the exception for further assertions.

## Lifecycle

```kotlin
ShouldSpec({
    beforeSpec { /* once per spec class */ }
    afterSpec  { /* once per spec class */ }
    beforeTest { /* before every should {} */ }
    afterTest  { /* after every should {}  */ }
})
```

Prefer `beforeTest` over `beforeSpec` unless the setup is genuinely stateless and expensive to repeat.

## Mocking

Use MockK (not Mockito) with Kotlin suspend functions:

```kotlin
val repo = mockk<UserRepository>()
coEvery { repo.findById(any()) } returns user
coVerify { repo.findById(userId) }
```

Use `relaxed = true` only in exploratory tests. Prefer explicit stubs in production test suites.

## Data-Driven Testing

```kotlin
withData(
    "alice" to 1,
    "bob"   to 2,
) { (name, expected) ->
    UserService.rankOf(name) shouldBe expected
}
```

Use `forAll` for property-based tests:

```kotlin
checkAll<String, Int> { s, i ->
    encode(decode(s, i)) shouldBe s
}
```

## Async Testing

Kotest runs coroutines natively inside specs — no special wrapper needed for `suspend` functions.
For flows, use `collect` or `toList()` within the test block. For turbine integration:

```kotlin
myFlow.test {
    awaitItem() shouldBe First
    awaitComplete()
}
```

## What NOT to Test

- Private methods — test them via their public interface
- Framework wiring (Spring dependency injection) — use integration tests for that layer
- Data classes' `equals`/`hashCode`/`toString` — Kotlin generates these correctly
- Trivial property accessors with no logic

## Anti-Patterns

- `Thread.sleep()` — use coroutine delays or virtual time
- Sharing mutable state between `should` blocks without reset in `beforeTest`
- Asserting on log output to verify business logic
- One giant spec file for multiple unrelated classes
- `shouldNotThrow<Any>()` as a pass-all catch-all
