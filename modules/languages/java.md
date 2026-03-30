# Java Language Conventions

## Type System

- Use Java records (`record XxxResponse(...)`) for immutable DTOs — they auto-generate constructor, accessors, `equals`, `hashCode`, and `toString`.
- Use `var` for local variable type inference when the type is obvious from the right-hand side; avoid it when it obscures the type.
- Use sealed interfaces/classes (Java 17+) for fixed-variant type hierarchies; pair with pattern matching `switch` for exhaustive dispatch.
- Use text blocks (`"""..."""`, Java 13+) for multi-line strings — SQL queries, JSON templates, HTML snippets.
- Use `UUID` (not sequential `Long`) for externally exposed entity identifiers.
- Prefer `List.of()`, `Map.of()`, `Set.of()` for immutable collections.

## Null Safety / Error Handling

- Use `Optional<T>` for values that may legitimately be absent — primarily as return types from repository/finder methods.
- Never call `Optional.get()` without a preceding `isPresent()` check — use `orElse()`, `orElseThrow()`, or `ifPresent()`.
- Do not use `Optional` as a method parameter or field type — it is a return-value convention only.
- Throw specific, typed exceptions rather than broad `Exception` catches — callers need to distinguish error types.
- Domain exceptions should carry meaningful messages and map to appropriate HTTP/response codes at the boundary layer.

## Streams API

- Prefer the Streams API over imperative loops for collection transformations, filtering, and aggregation.
- Use method references (`User::getName`) over lambdas when the lambda simply delegates to an existing method.
- For simple `List.of()` → single-step transform, a for-each loop is more readable than a stream.
- Collect with explicit collectors: `Collectors.toList()`, `Collectors.toUnmodifiableList()`, `Collectors.groupingBy()`.
- Avoid side effects in stream operations (`forEach` is for terminal consumption, not for building results via mutation).

## Date and Time

- Use `java.time.*` exclusively — never `java.util.Date`, `java.util.Calendar`, or `java.sql.Timestamp` in new code.
- `Instant` for machine-readable timestamps; `LocalDate` / `LocalDateTime` for human-readable date/time without timezone; `ZonedDateTime` when timezone context matters.
- Store and transmit timestamps as UTC; convert to user timezone only at display layer.

## Concurrency

- Use `CompletableFuture<T>` for async operations that callers need to compose or await.
- Background tasks: `@Async` with a custom `TaskExecutor` — never rely on the default unbounded executor.
- `@Async` does not work on `private` methods (proxy-based AOP bypasses the proxy).
- `@Transactional` and `@Async` on the same method lose the transaction (runs in a new thread without the original transaction context).
- Use `java.util.concurrent` primitives (`ReentrantLock`, `CountDownLatch`, `Semaphore`) over `synchronized` for explicit concurrency control.

## Naming Idioms

- Classes: `PascalCase`. Methods and fields: `camelCase`. Constants: `UPPER_SNAKE_CASE`.
- Boolean getters: `isX()` / `hasX()` — not `getIsX()`.
- Builders: `XxxBuilder` with fluent `withField(value)` methods.
- Factory methods: `of(...)`, `from(...)`, `create(...)` as static factory convention.
- Test classes: `XxxTest` (unit) or `XxxIT` (integration).

## Logging

- Use **SLF4J** (`org.slf4j:slf4j-api`) as the logging facade — decouples application code from the logging implementation.
- Backend: **Logback** (`ch.qos.logback:logback-classic`) with JSON encoder (`net.logstash.logback:logstash-logback-encoder`) for structured output.
- Obtain a logger per class:
  ```java
  private static final Logger log = LoggerFactory.getLogger(MyService.class);
  ```
- Use parameterized messages — SLF4J evaluates arguments only when the level is enabled:
  ```java
  log.info("Order created: orderId={}", order.getId());
  log.debug("Payment details: provider={}, amount={}", payment.getProvider(), payment.getAmount());
  log.error("Payment failed: orderId={}", order.getId(), exception);
  ```
- Use MDC for request-scoped context (correlation ID, trace ID) — set once in a filter, cleared in `finally`:
  ```java
  MDC.put("correlation_id", correlationId);
  try { chain.doFilter(request, response); }
  finally { MDC.clear(); }
  ```
- Use fluent logging API (SLF4J 2.0+) for conditional structured fields:
  ```java
  log.atDebug().addKeyValue("itemCount", items.size()).log("Processing batch");
  ```
- Never use `System.out.println`, `System.err.println`, or `printStackTrace()` — they bypass structured logging, lack levels, and cannot be routed or filtered.
- Never use string concatenation in log messages (`log.debug("user=" + user)`) — it evaluates regardless of log level. Use parameterized messages.
- Never log PII (email, name, phone), credentials (tokens, passwords, API keys), or financial data (card numbers). Log internal IDs (`userId`, `orderId`) instead.

## Anti-Patterns

- **Field injection (`@Autowired` on fields):** Hides dependencies, breaks testability, and cannot use `final`. Always use constructor injection.
- **Raw `Optional.get()`:** Throws `NoSuchElementException` without context. Use `orElseThrow(SpecificException::new)`.
- **Mutable statics:** Class-level `static` mutable state makes code non-thread-safe and untestable. Use dependency injection.
- **Catching `Exception` or `Throwable` broadly:** Swallows unrelated errors. Catch the most specific type that you can meaningfully handle.
- **`new Date()` / `System.currentTimeMillis()` for domain timestamps:** Use `java.time.Instant.now()` — testable, unambiguous, timezone-aware.
- **Circular service dependencies:** Indicates missing abstraction. Extract a shared domain service or event to break the cycle.
- **`System.out.println` in production:** Use SLF4J (`LoggerFactory.getLogger(...)`) with structured logging.

## Dos
- Use `record` (Java 16+) for immutable data carriers — auto-generated `equals`, `hashCode`, `toString`.
- Use `Optional<T>` for return types that may be absent — never for parameters or fields.
- Use `var` (Java 10+) for local variables when the type is obvious from the right-hand side.
- Use `Stream` API for collection transformations — declarative, parallelizable, composable.
- Use `java.time` (`Instant`, `LocalDate`, `ZonedDateTime`) — never `Date` or `Calendar`.
- Use `sealed` classes/interfaces (Java 17+) with pattern matching for exhaustive type hierarchies.
- Use `try-with-resources` for all `AutoCloseable` resources — never manually close in `finally`.

## Don'ts
- Don't use raw types (`List` instead of `List<String>`) — they bypass compile-time type checking.
- Don't catch `Exception` or `Throwable` broadly — catch the most specific exception type you can handle.
- Don't use `null` to represent "empty" — use `Optional` for returns, empty collections for lists.
- Don't use `System.out.println` for logging — use SLF4J with structured context.
- Don't use mutable static fields — they create hidden global state and thread-safety issues.
- Don't use `new Date()` for timestamps — use `Instant.now()` for unambiguous UTC timestamps.
- Don't use `==` to compare objects (except primitives) — use `.equals()` or `Objects.equals()`.
- Don't avoid modern Java features — use records (16+), sealed classes (17+), pattern matching (21+). Pre-Java 17 patterns are legacy.
- Don't write utility classes with `private` constructor — use static methods on relevant domain types or consider if a record fits.
- Don't use raw `Map<String, Object>` for structured data — define a record.
