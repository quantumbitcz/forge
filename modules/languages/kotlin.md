# Kotlin Language Conventions
> Support tier: contract-verified
## Type System

- Use `kotlin.uuid.Uuid` for UUIDs in domain code; convert to `java.util.UUID` only at persistence boundaries via `toJavaUuid()` / `toKotlinUuid()`.
- Use `kotlinx.datetime.Instant` for timestamps in domain code; convert to `java.time.Instant` only at persistence boundaries via `toJavaInstant()` / `toKotlinInstant()`.
- Prefer `data class` for value objects and DTOs — never for entities where identity matters.
- Use `@JvmInline value class` to wrap primitives into typed IDs (e.g., `value class UserId(val value: Uuid)`).
- Sealed interfaces/classes for domain models with a fixed set of variants — exhaustive `when` is enforced at compile time.
- Trailing commas required in multi-line parameter and argument lists.

## Null Safety / Error Handling

- Never use `!!` (non-null assertion operator) — it converts a compile-time safety guarantee into a runtime crash.
- For required lookups that may return null: `?: throw NoSuchElementException("message")` or `requireNotNull(value) { "message" }`.
- Use `?.let { }` for null-safe transformation chains.
- Use `require()` for preconditions on inputs; `check()` for preconditions on state.
- Use `kotlin.Result` or sealed classes for expected failures; throw exceptions only for unexpected/programming errors.
- Do not mix Java `Optional<T>` with Kotlin nullable — use Kotlin `T?` in core; convert at adapter boundaries.

## Concurrency

- All I/O-bound methods should be `suspend` functions — callers control the scope and dispatcher.
- Use `supervisorScope` for parallel tasks that should be independently cancellable (one child failure does not cancel siblings).
- Do not catch `CancellationException` broadly — it breaks structured cancellation.
- Use coroutine scope functions (`coroutineScope`, `supervisorScope`) rather than `GlobalScope` for bounded work.
- Convert reactive `Flow` to `List` at adapter/boundary layers, not in the core domain.

## Naming Idioms

- Interface names: `ISomething` (use-case and port interfaces follow this pattern).
- Implementation names: `ISomethingImpl` (pairs with its interface).
- Extension functions: group in dedicated `*Extensions.kt` files, not scattered across classes.
- `when` expression: always prefer the exhaustive expression form over `if-else` chains for type/state dispatch.
- Package names: `lowercase.dotted.path`, no underscores, no camelCase.

## Scope Functions

Use the right scope function for the intent — confusion leads to bugs:

| Function | Object ref | Return      | Use when                               |
|----------|-----------|-------------|----------------------------------------|
| `let`    | `it`      | lambda result | Null-safe chaining, transforming      |
| `run`    | `this`    | lambda result | Computing a value within object context|
| `apply`  | `this`    | object      | Configuring/initializing an object     |
| `also`   | `it`      | object      | Side effects (logging, validation)     |
| `with`   | `this`    | lambda result | Non-null object with multiple calls   |

## Logging

- Use **kotlin-logging** (`io.github.oshai:kotlin-logging-jvm`) — wraps SLF4J with Kotlin idioms and lambda-based lazy evaluation.
- Backend: **Logback** (`ch.qos.logback:logback-classic`) with JSON encoder (`net.logstash.logback:logstash-logback-encoder`) for structured output.
- Obtain a logger per class using the top-level factory:
  ```kotlin
  private val logger = KotlinLogging.logger {}
  ```
- Use lambda syntax for all log calls — the message is only constructed if the level is enabled:
  ```kotlin
  logger.info { "Order created: orderId=${order.id}" }
  logger.debug { "Payment details: provider=${payment.provider}, amount=${payment.amount}" }
  logger.error(exception) { "Payment failed: orderId=${order.id}" }
  ```
- Use MDC for request-scoped context (correlation ID, trace ID) — set once in a filter/interceptor, not per call site:
  ```kotlin
  MDC.put("correlation_id", correlationId)
  try { chain.proceed(request) } finally { MDC.clear() }
  ```
- For coroutines, use `MDCContext()` from `kotlinx-coroutines-slf4j` to propagate MDC across coroutine boundaries:
  ```kotlin
  withContext(MDCContext()) {
      // MDC values are available in this coroutine and its children
  }
  ```
- Never use `println()` for operational logging — it lacks levels, structure, and MDC context.
- Never log with string concatenation or string templates outside a lambda — use the lambda syntax which skips evaluation when the level is disabled.
- PII/credential/financial data logging rules: see `shared/logging-rules.md`.
- Use `also` scope function for inline logging during transformation chains:
  ```kotlin
  findUser(id)
      ?.also { logger.debug { "Found user: id=${it.id}" } }
      ?.let { createOrder(it) }
  ```

## Anti-Patterns

- **`!!` usage:** Every `!!` is a deferred `NullPointerException`. Fix the nullability model instead.
- **`lateinit` misuse:** Cannot be used with primitive or nullable types. Throws `UninitializedPropertyAccessException` (not NPE) on premature access. Prefer `lazy` for computed properties or constructor initialization for required dependencies.
- **Mutable properties in data classes:** All `data class` properties should be `val`. Mutable data classes defeat value semantics.
- **Mutable collection exposure:** Never return `MutableList<T>` from domain models — return `List<T>` backed by `.toList()` to prevent external mutation.
- **Catching `Exception` broadly:** Catch specific types. Especially in coroutines — do not catch `CancellationException` unless you re-throw it.
- **`var` instead of `val`:** Default to `val`; use `var` only when reassignment is genuinely required.
- **Global mutable state:** Avoid `object` singletons with mutable state — use dependency injection instead.

## Dos
- Use `val` by default — immutability prevents entire classes of concurrency bugs.
- Use `sealed class`/`sealed interface` for exhaustive `when` expressions — the compiler enforces completeness.
- Use `data class` for value objects — `equals`, `hashCode`, `copy`, and `toString` are generated.
- Use coroutines with structured concurrency (`coroutineScope`, `supervisorScope`) — never `GlobalScope`.
- Prefer coroutines over Java threads/`ExecutorService` for all async and concurrent work — coroutines are lighter, cancellable, and integrate with structured concurrency.
- Use extension functions to add behavior without inheritance — keeps classes focused.
- Use `require`/`check`/`error` for preconditions — they throw `IllegalArgumentException`/`IllegalStateException` with clear messages.
- Use `?.let { }` or `?.run { }` for null-safe operations instead of `if (x != null)` blocks.

## Don'ts
- Don't catch `CancellationException` without re-throwing — it breaks structured concurrency cancellation.
- Don't use `!!` (not-null assertion) — it throws `NullPointerException` at runtime; use `?.` or `requireNotNull`.
- Don't use `var` in `data class` properties — it defeats value semantics and `copy()` behavior.
- Don't expose `MutableList`/`MutableMap` from public APIs — return read-only `List`/`Map` via `.toList()`.
- Don't use `object` singletons for stateful services — use dependency injection for testability.
- Don't use `runBlocking` in coroutine contexts — it blocks the thread and can cause deadlocks.
- Don't use Java's `synchronized` with coroutines — use `Mutex` from `kotlinx.coroutines.sync`.
- Don't use Java threads (`Thread`, `ExecutorService`, `CompletableFuture`) when coroutines are available — they lack structured concurrency, cancellation propagation, and are heavier.
- Don't use the Builder pattern — use named/default arguments + `copy()` on data classes.
- Don't use the null-object pattern — use sealed classes/interfaces with an explicit `None` variant.
- Don't create static utility classes — use top-level functions or extension functions.
- Don't write explicit getter/setter methods — use properties with custom `get()`/`set()` if needed.
- Don't use `if-else` chains on type checks — use `when` with sealed type exhaustive matching.
- Don't use Java's `Stream` API — use Kotlin stdlib collection operations (`map`, `filter`, `fold`) or `Sequence` for lazy evaluation.
- Don't use `Optional<T>` — use nullable types `T?` with `?.`, `?:`, `let`.
- Don't use Java `Iterable`/`Iterator` — use Kotlin `Sequence` for lazy evaluation.
- Don't use checked exception patterns — use `Result<T>` or sealed class error hierarchies.
