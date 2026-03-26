# Dart Language Conventions

## Type System

- Dart has sound null safety (since Dart 2.12) — all types are non-nullable by default.
- Use `?` suffix for nullable types: `String? name`.
- Use type inference with `var` for local variables when the type is obvious; use explicit types for public APIs.
- Use `final` for values assigned once; `const` for compile-time constants.
- Use generics for type-safe collections and classes: `List<User>`, `Future<Result<Order, Error>>`.
- Use `typedef` for function type aliases: `typedef Predicate<T> = bool Function(T)`.
- Max line length: 80 characters (Dart convention).

## Null Safety / Error Handling

- Use null-aware operators: `?.` (conditional access), `??` (null coalescing), `??=` (null-aware assignment), `!` (null assertion — use sparingly).
- Use `late` for lazily initialized non-nullable variables — but only when initialization is guaranteed before access.
- Use `try/catch/finally` with typed catches: `on FormatException catch (e)`.
- Use `Result` types (custom or from packages like `dartz` or `fpdart`) for expected failures instead of exceptions.
- Use `assert` for development-only invariant checks — they're stripped in release builds.
- Never catch `Error` — it represents programming bugs (stack overflow, assertion failure), not recoverable conditions.

## Async / Concurrency

- Use `async`/`await` for all asynchronous operations — Dart has first-class async support.
- Use `Future.wait()` for concurrent async operations: `await Future.wait([fetchA(), fetchB()])`.
- Use `Stream` for reactive data flows and event sequences.
- Use `Isolate` for CPU-intensive work — Dart's Isolates provide true parallelism without shared memory.
- Use `compute()` for simple background computations: `final result = await compute(parseJson, rawData)`.
- Never block the UI thread (main isolate) with synchronous computation in Flutter apps.
- Use `StreamController` for custom streams; prefer `broadcast()` streams for multiple listeners.

## Idiomatic Patterns

- **Cascade operator** (`..`) for chaining method calls on the same object:
  ```dart
  final button = TextButton()
    ..text = 'Click me'
    ..onPressed = handleClick;
  ```
- **Collection literals**: `[1, 2, 3]`, `{key: value}`, `{1, 2, 3}` (Set).
- **Collection if/for**: `[if (showHeader) Header(), for (var item in items) ListTile(title: Text(item))]`.
- **Extension methods** for adding functionality to existing types without subclassing.
- **Pattern matching** (Dart 3.0+): `switch (shape) { case Circle(radius: var r): ... }`.
- **Sealed classes** (Dart 3.0+) for exhaustive pattern matching: `sealed class Shape {}`.
- **Named constructors** for clarity: `User.fromJson(json)`, `User.guest()`.

## Naming Idioms

- Files: `snake_case.dart`.
- Classes, enums, extensions, mixins, typedefs: `PascalCase`.
- Functions, methods, variables, parameters: `camelCase`.
- Constants: `camelCase` (Dart convention — not `UPPER_SNAKE_CASE`).
- Private members: single leading underscore (`_privateMethod`).
- Libraries: `snake_case`.
- Boolean variables: `isActive`, `hasPermission`, `canDelete`.

## Anti-Patterns

- **Using `dynamic` everywhere** — disables type checking entirely. Use `Object?` when you truly need an any-type.
- **Null assertion (`!`) abuse** — throws at runtime if null. Use null-aware operators or explicit null checks instead.
- **Using `late` for fields that might not be initialized** — throws `LateInitializationError` at runtime.
- **Synchronous I/O in async contexts** — `File.readAsStringSync()` blocks the event loop; use `readAsString()`.
- **Mutable global state** — use `Provider`, `Riverpod`, or dependency injection instead of top-level `var`.

## Dos
- Use sound null safety — let the type system prevent null reference errors at compile time.
- Use `final` for all variables that don't need reassignment — it communicates intent and prevents bugs.
- Use `async`/`await` consistently — never mix `.then()` chains with `await` in the same function.
- Use `Isolate` or `compute()` for CPU-heavy work — keep the main isolate responsive.
- Use `sealed class` (Dart 3.0+) with pattern matching for type-safe state handling.
- Use extension methods to add functionality to types you don't own.
- Run `dart analyze` and `dart format` as part of CI — Dart's analyzer catches more issues than most linters.

## Don'ts
- Don't use `dynamic` as a substitute for proper typing — it disables all type safety.
- Don't abuse null assertion (`!`) — it defeats the purpose of null safety.
- Don't use `late` for fields that may never be initialized — it throws at runtime.
- Don't catch `Error` — it's for programming bugs, not recoverable conditions.
- Don't use `print()` for logging — use the `logging` package or a structured logging solution.
- Don't use mutable top-level variables — they create hidden global state.
- Don't ignore `dart analyze` warnings — they indicate real code quality issues.
