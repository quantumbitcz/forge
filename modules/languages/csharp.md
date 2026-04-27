# C# Language Conventions
> Support tier: contract-verified
## Type System

- Enable `#nullable enable` (or set `<Nullable>enable</Nullable>` in the project file) — nullable reference types make `null` explicit and compiler-enforced.
- Use `record` for immutable data containers — the compiler generates constructor, `Equals`, `GetHashCode`, `ToString`, and deconstruction automatically.
  - `record class` for reference-type records (heap allocated, reference equality by default but `record` overrides it to value equality).
  - `record struct` for value-type records (stack allocated, fully value-semantic).
- Use `init`-only properties (`{ get; init; }`) for settable-at-construction-time but immutable-after-construction properties.
- Use primary constructors (C# 12+) for concise class/struct definitions: `class UserService(IUserRepository repo)`.
- Use `required` members (C# 11+) to enforce that callers initialize essential properties.
- Use sealed classes for domain types that should not be subclassed — enables pattern-matching exhaustiveness.

## Null Safety / Nullable Reference Types

- With `#nullable enable`, reference types are non-nullable by default — `string` cannot be null; `string?` can.
- Never use `null!` (null-forgiving operator) without a comment explaining why the compiler's analysis is wrong.
- Use the null-conditional operator (`?.`) and null-coalescing (`??`, `??=`) for concise null handling.
- Use pattern matching (`is null`, `is not null`) instead of `== null` for readability and null-state analysis.
- Use `ArgumentNullException.ThrowIfNull(param)` (C# 10+ / .NET 6+) at public API boundaries instead of manual null checks.

## Pattern Matching

- Use `is` patterns for type checks and variable binding: `if (shape is Circle c) { ... }`.
- Use `switch` expressions (C# 8+) for multi-branch type dispatch — more concise and exhaustiveness-checked than `switch` statements:
  ```csharp
  string Describe(Shape shape) => shape switch
  {
      Circle c  => $"Circle r={c.Radius}",
      Rect r    => $"Rect {r.Width}x{r.Height}",
      _         => "Unknown"
  };
  ```
- Use property patterns: `if (order is { Status: OrderStatus.Pending, Total: > 100 })`.
- Use list patterns (C# 11+): `if (items is [var first, .., var last])`.
- Prefer `switch` expressions over long `if-else` chains for value-returning dispatch.

## Async / Await

- Use `async Task<T>` for methods that return a value; `async Task` for void-return async methods.
- Never use `async void` except for event handlers — unhandled exceptions in `async void` crash the process.
- Use `ValueTask<T>` when a method frequently completes synchronously (e.g., cache hits) — avoids heap allocation for the common path.
- Use `ConfigureAwait(false)` in library code to avoid capturing the synchronization context unnecessarily.
- Use `CancellationToken` as the last parameter in all async public methods — propagate it to all I/O calls.
- Use `Task.WhenAll` for concurrent independent operations; `Task.WhenAny` when the first result wins.
- Never use `Task.Result` or `.Wait()` synchronously — can deadlock in synchronization-context environments (e.g., ASP.NET).

## LINQ

- Prefer method syntax (`Where`, `Select`, `OrderBy`) over query syntax for most cases — it composes better and is consistent with the codebase.
- Use query syntax when it reads more naturally (complex joins, groupings with `into`).
- Avoid side effects in LINQ lambdas (`Select`, `Where`) — LINQ chains should be pure transformations.
- Be aware of deferred execution: `IEnumerable<T>` LINQ chains are not executed until enumerated. Call `.ToList()` / `.ToArray()` to materialize and avoid repeated enumeration.
- Prefer `FirstOrDefault()` over `First()` when the element may be absent — `First()` throws if empty.
- Use `Any()` instead of `Count() > 0` — `Any()` short-circuits.

## Strings

- Use string interpolation (`$"Hello, {name}!"`) — more readable and less error-prone than `string.Format`.
- Use raw string literals (C# 11+, `"""..."""`) for multi-line strings, embedded JSON, SQL, and regex patterns — no escape sequences needed.
- Use `@"..."` verbatim strings for file paths and other content with backslashes.
- Prefer `string.IsNullOrWhiteSpace` over `string.IsNullOrEmpty` when whitespace-only strings should also be treated as empty.
- Use `StringBuilder` for concatenation in loops — `+` in a loop is O(n²).
- Use `string.Equals(a, b, StringComparison.OrdinalIgnoreCase)` for case-insensitive comparisons — do not rely on `ToLower()` equality.

## Naming Idioms

- Types, methods, properties, events: `PascalCase`.
- Local variables and parameters: `camelCase`.
- Private fields: `_camelCase` (underscore prefix).
- Constants: `PascalCase` (C# convention) or `UPPER_SNAKE_CASE` for interop constants.
- Interfaces: `IPascalCase` prefix (e.g., `IUserRepository`).
- Async methods: suffix with `Async` (e.g., `GetUserAsync`).
- Boolean properties: `IsX`, `HasX`, `CanX`.

## Logging

- Use **`Microsoft.Extensions.Logging`** (`ILogger<T>`) — the built-in DI-friendly logging abstraction in .NET.
- Structured backend: **Serilog** (`Serilog` + `Serilog.Extensions.Logging`) with JSON sink for structured output.
- Inject `ILogger<T>` via constructor — never create loggers manually:
  ```csharp
  public class OrderService(ILogger<OrderService> logger)
  {
      public async Task<Order> CreateOrderAsync(CreateOrderCommand cmd)
      {
          logger.LogInformation("Order created: {OrderId} for {UserId}", order.Id, cmd.UserId);
      }
  }
  ```
- Use **message templates** (not string interpolation) — Serilog/MEL captures named properties as structured data:
  ```csharp
  // Correct — structured, queryable as separate fields
  logger.LogInformation("Order created: {OrderId} for {UserId}", order.Id, user.Id);

  // Wrong — baked into the message string, not queryable
  logger.LogInformation($"Order created: {order.Id} for {user.Id}");
  ```
- Use `[LoggerMessage]` source generator (.NET 6+) for high-performance, zero-allocation logging:
  ```csharp
  [LoggerMessage(Level = LogLevel.Information, Message = "Order created: {OrderId}")]
  static partial void LogOrderCreated(ILogger logger, string orderId);
  ```
- Use scopes for request-level context (correlation ID, trace ID):
  ```csharp
  using (logger.BeginScope(new Dictionary<string, object> { ["CorrelationId"] = correlationId }))
  {
      // All log entries within this scope include CorrelationId
  }
  ```
- Never use `Console.WriteLine` for logging — it lacks levels, structure, and DI integration.
- PII/credential/financial data logging rules: see `shared/logging-rules.md`.

## Anti-Patterns

- **`async void` methods:** Exceptions escape the caller's `try/catch`. Only acceptable for event handlers; always wrap the body in a `try/catch`.
- **`.Result` / `.Wait()` blocking on async:** Can deadlock when a synchronization context is present. Use `await` all the way up.
- **Deferred LINQ enumerated multiple times:** An `IEnumerable<T>` from a LINQ chain re-executes on each `foreach`. Materialize with `.ToList()` when the result is used more than once.
- **`null!` to silence warnings:** Suppresses the nullable analysis without fixing the root cause. Investigate and fix the nullability model.
- **`catch (Exception)` broadly:** Swallows `OutOfMemoryException`, `StackOverflowException`, and other fatal errors. Catch specific, handleable exceptions.
- **Mutable shared state in static fields:** Thread-unsafe without explicit synchronization. Use dependency injection for shared services.
- **`string.Format` over interpolation:** Harder to read, more error-prone with index mismatches. Use `$""` interpolation.
- **Magic numbers/strings:** Replace with named constants, `enum` values, or `static readonly` fields with intent-describing names.

## Dos
- Use `record` (C# 9+) for immutable value objects — auto-generated equality, hashing, and deconstruction.
- Use `required` properties (C# 11+) to enforce initialization at construction time.
- Use pattern matching (`is`, `switch` expressions) for type-safe branching.
- Use `async`/`await` throughout — never mix sync and async code.
- Use LINQ for collection transformations — it's declarative and composable.
- Use nullable reference types (`#nullable enable`) to catch null bugs at compile time.
- Use `IAsyncDisposable` and `await using` for async resource cleanup.

## Don'ts
- Don't use `async void` methods — exceptions escape the caller's try/catch; only acceptable for event handlers.
- Don't use `.Result` or `.Wait()` on async tasks — it can deadlock when a synchronization context is present.
- Don't use `null!` to silence nullable warnings — fix the underlying nullability model.
- Don't catch `Exception` broadly — it swallows `OutOfMemoryException` and other fatal errors.
- Don't use mutable shared state in static fields — thread-unsafe without explicit synchronization.
- Don't use `string.Format` when `$""` interpolation is available — it's harder to read.
- Don't use `dynamic` unless interop requires it — it disables compile-time type checking.
- Don't write Java-style `IFooService`/`FooService` pairs for everything — only create an interface when multiple implementations exist or for testability at system boundaries.
- Don't use `class` for DTOs — use `record` (C# 9+) for immutable data carriers.
- Don't write `Task.Result` or `.Wait()` — use `await` consistently; mixing sync and async causes deadlocks.
