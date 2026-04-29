# ScalaTest Best Practices

> Support tier: contract-verified

## Overview
ScalaTest is the most popular testing framework for Scala, supporting multiple testing styles (FunSuite, FlatSpec, WordSpec, FreeSpec). Use it for unit and integration tests in Scala/Akka/Play applications. ScalaTest excels at flexible DSLs, matchers, and async testing. Avoid it for non-Scala JVM projects (use JUnit5/Kotest).

## Conventions

### Test Structure (FunSuite style)
```scala
class UserServiceTest extends AnyFunSuite with Matchers:

  test("create user with valid data"):
    val service = UserService(mockRepo)
    val result = service.createUser("alice@example.com", "Alice")
    result shouldBe Right(User(email = "alice@example.com", name = "Alice"))

  test("reject user with invalid email"):
    val service = UserService(mockRepo)
    val result = service.createUser("not-email", "Alice")
    result shouldBe a[Left[_, _]]
    result.left.value shouldBe ValidationError("Invalid email")
```

### Async Testing
```scala
class ApiServiceTest extends AsyncFunSuite with Matchers:

  test("fetch user returns user data"):
    val service = ApiService(httpClient)
    service.fetchUser("123").map: user =>
      user.email shouldBe "alice@example.com"
```

### Property-Based Testing (ScalaCheck)
```scala
class StringUtilsTest extends AnyFunSuite with ScalaCheckPropertyChecks:

  test("slugify is idempotent"):
    forAll: (s: String) =>
      whenever(s.nonEmpty):
        slugify(slugify(s)) shouldBe slugify(s)
```

## Configuration

```scala
// build.sbt
libraryDependencies ++= Seq(
  "org.scalatest" %% "scalatest" % "3.2.18" % Test,
  "org.scalatestplus" %% "scalacheck-1-17" % "3.2.18.0" % Test
)
```

## Dos
- Pick one testing style per project (FunSuite recommended for Scala 3) — consistency matters more than style.
- Use `Matchers` trait for readable assertions: `result shouldBe expected`.
- Use `AsyncFunSuite` for testing `Future`-based code — it handles async assertions natively.
- Use `ScalaCheckPropertyChecks` for property-based testing of pure functions.
- Use `BeforeAndAfterEach` for test setup/teardown — not manual initialization.
- Use `eventually` from ScalaTest for retrying flaky async assertions with timeout.
- Use Testcontainers-scala for database integration tests.

## Don'ts
- Don't mix testing styles in one project — pick FunSuite or FlatSpec and be consistent.
- Don't use `Await.result` in tests — use `AsyncFunSuite` for proper async testing.
- Don't test implementation details — test behavior through public interfaces.
- Don't use `var` in test classes — use `val` with lazy initialization or `BeforeAndAfterEach`.
- Don't ignore `eventually` timeout warnings — they indicate real timing issues.
- Don't skip property-based tests for pure functions — they catch edge cases you wouldn't think to test.
- Don't mock concrete classes — use traits/interfaces and mock those.
