# Kotlin Language Conventions

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

## Anti-Patterns

- **`!!` usage:** Every `!!` is a deferred `NullPointerException`. Fix the nullability model instead.
- **`lateinit` misuse:** Cannot be used with primitive or nullable types. Throws `UninitializedPropertyAccessException` (not NPE) on premature access. Prefer `lazy` for computed properties or constructor initialization for required dependencies.
- **Mutable properties in data classes:** All `data class` properties should be `val`. Mutable data classes defeat value semantics.
- **Mutable collection exposure:** Never return `MutableList<T>` from domain models — return `List<T>` backed by `.toList()` to prevent external mutation.
- **Catching `Exception` broadly:** Catch specific types. Especially in coroutines — do not catch `CancellationException` unless you re-throw it.
- **`var` instead of `val`:** Default to `val`; use `var` only when reassignment is genuinely required.
- **Global mutable state:** Avoid `object` singletons with mutable state — use dependency injection instead.
