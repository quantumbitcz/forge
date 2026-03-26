# Scala Language Conventions

## Type System

- Scala has a powerful, sound type system with type inference, algebraic data types, and higher-kinded types.
- Use `val` (immutable) by default; `var` (mutable) only when strictly necessary.
- Use `sealed trait` / `sealed abstract class` + `case class` / `case object` for ADTs (sum types).
- Use type parameters with variance annotations: `trait Container[+A]` (covariant), `trait Sink[-A]` (contravariant).
- Use `given`/`using` (Scala 3) or `implicit` (Scala 2) for type class instances and dependency injection.
- Use opaque types (Scala 3) or `AnyVal` wrappers (Scala 2) for zero-cost type-safe wrappers.
- Max line length: 120 characters.

## Null Safety / Error Handling

- Never use `null` in Scala — use `Option[T]` for optional values.
- Use `Either[Error, Success]` for operations that can fail with typed errors.
- Use `Try[T]` for operations that may throw exceptions (interop with Java libraries).
- Pattern match on ADTs for exhaustive error handling:
  ```scala
  result match
    case Right(user) => ok(user)
    case Left(NotFound(id)) => notFound(s"User $id not found")
    case Left(ValidationError(msg)) => badRequest(msg)
  ```
- Use `for` comprehensions to chain `Option`, `Either`, `Future`, and other monadic types.
- Use `NonEmptyList` / `NonEmptyChain` (from Cats) for collections that must have at least one element.

## Async / Concurrency

- Use `Future` for basic async operations; use **Cats Effect** (`IO`) or **ZIO** for referentially transparent async.
- Use structured concurrency: `IO.parMapN(fetchA, fetchB)((a, b) => combine(a, b))`.
- Use `Ref` (from Cats Effect/ZIO) for thread-safe mutable state — not `var` with locks.
- Use **Akka/Pekko** actors for distributed systems and complex stateful concurrency.
- Never use `Await.result` in production — it blocks threads. Use `for`/`map`/`flatMap` on `Future`/`IO`.
- Use `ExecutionContext.parasitic` only for very lightweight continuations — it reuses the calling thread.

## Idiomatic Patterns

- **For comprehensions** for composing monadic operations:
  ```scala
  for
    user <- findUser(id)
    order <- createOrder(user, items)
    _ <- sendConfirmation(user, order)
  yield order
  ```
- **Pattern matching** on case classes, sealed traits, tuples, and literals.
- **Extension methods** (Scala 3): `extension (s: String) def toSlug: String = ...`.
- **Type classes** via `given`/`using` for ad-hoc polymorphism:
  ```scala
  trait JsonEncoder[A]:
    def encode(a: A): Json
  given JsonEncoder[User] with
    def encode(u: User) = ...
  ```
- **Immutable collections** by default (`List`, `Vector`, `Map`, `Set`).
- **Case classes** for data objects — they provide `equals`, `hashCode`, `copy`, and pattern matching.

## Naming Idioms

- Files: `PascalCase.scala` (matching the primary type).
- Classes, traits, objects: `PascalCase`.
- Methods, values, variables: `camelCase`.
- Constants: `PascalCase` (Scala convention — `MaxRetries`, not `MAX_RETRIES`).
- Type parameters: single uppercase letter (`A`, `B`) or descriptive (`F[_]`, `Effect`).
- Packages: `lowercase.dotted` (`com.myapp.users`).
- Boolean methods: `isEmpty`, `isValid`, `hasPermission`.

## Anti-Patterns

- **Using `null`** — Scala has `Option[T]`; `null` bypasses the type system entirely.
- **Blocking inside `Future`** — `Await.result` blocks threads; use `map`/`flatMap` instead.
- **Using `Any` or `AnyRef`** — defeats type safety; use generics or ADTs.
- **Overusing implicits** (Scala 2) — implicit conversions create confusing control flow. Scala 3's `given`/`using` is more explicit.
- **Mutable collections in concurrent code** — use `Ref`, `AtomicReference`, or immutable collections with copy-on-write.

## Dos
- Use `val` by default — mutability should be the exception, not the rule.
- Use `Option[T]` instead of `null` — pattern match for safe access.
- Use `sealed trait` + `case class` for domain modeling — enables exhaustive pattern matching.
- Use `for` comprehensions for chaining `Option`, `Either`, `Future`, and `IO`.
- Use the Scala 3 syntax (`given`/`using`, `extension`, `enum`) for new code.
- Use sbt's `scalafmtAll` for consistent formatting.
- Use `Either[DomainError, Success]` for typed error handling instead of exceptions.

## Don'ts
- Don't use `null` — use `Option[T]` for optional values.
- Don't use `return` — it's a non-local return that can escape closures and cause subtle bugs.
- Don't use `Await.result` in production code — it blocks threads and can cause deadlocks.
- Don't use mutable state (`var`, mutable collections) in concurrent code without synchronization.
- Don't use `Any` as a catch-all type — use generics or sealed hierarchies.
- Don't use implicit conversions (Scala 2) — they hide type transformations and confuse readers.
- Don't write Scala like Java — embrace functional patterns, immutability, and the type system.
