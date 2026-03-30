# Swift Language Conventions

## Type System

- **Value types over reference types:** Use `struct` for data models by default — value semantics eliminate a class of sharing/mutation bugs.
- Use `class` only when: identity matters (two instances are distinct even with identical data), inheritance is needed, or a shared mutable reference is genuinely required.
- Use `enum` with associated values for sum types (discriminated unions): `Result<T, Error>`, `Optional<T>`, custom domain states.
- Use `protocol` for defining interfaces and capabilities — prefer protocol-oriented design over deep class hierarchies.
- Use `typealias` to give domain-meaningful names to complex types.
- Use `Codable` (`Encodable + Decodable`) for JSON parsing — implement custom `CodingKeys` when API field names differ from Swift naming conventions.

## Optionals and Null Safety

- Swift's optional system (`T?`) enforces null safety at compile time — a non-optional value is guaranteed non-nil.
- Prefer `guard let` over nested `if let` for early returns — it reduces nesting and makes the happy path clear.
- Never force-unwrap (`!`) unless you can guarantee the value is non-nil (e.g., an `@IBOutlet` after `viewDidLoad`) — document why with a comment.
- Do not use `unowned` unless you can prove the reference will never outlive its owner — `[weak self]` is always the safer default.
- Use `compactMap`, `flatMap`, and optional chaining (`?.`) to work with optionals without unwrapping chains.

## Memory Safety

- **Retain cycles:** A retain cycle between two reference types keeps both alive indefinitely, leaking memory.
  - Closures stored as properties: always capture `[weak self]` when the closure might outlive the current instance.
  - Delegate patterns: declare delegates as `weak var delegate: SomeDelegate?` — delegates are back-references and should not extend object lifetime.
  - Timer callbacks: Timer retains its target; use `[weak self]` in the callback or invalidate the timer in `deinit`.
  - Notification observers (block-based): capture `[weak self]` or use Combine publishers (which handle this automatically).
- Use Instruments > Leaks and the Memory Graph Debugger to detect retain cycles during development.
- `struct` and `enum` (value types) cannot form retain cycles — prefer them where possible.

## Concurrency

- Use `async/await` for all asynchronous work — no completion handlers in new code.
- Annotate types that update UI state with `@MainActor` — ensures all property mutations and method calls happen on the main thread without `DispatchQueue.main.async`.
- Use `actor` for thread-safe mutable state in services and other non-UI reference types — the actor isolates its own state.
- Use `Task { }` to launch async work from synchronous contexts (button actions, lifecycle methods).
- Use `async let` for parallel independent tasks; use `withTaskGroup` for dynamic parallelism.
- Structured concurrency: prefer `async let` and task groups over `Task.detached` — structured tasks are automatically cancelled with their parent.
- Never use `DispatchQueue.main.async` in new SwiftUI/async code — use `@MainActor` or `await MainActor.run { }`.

## Protocol-Oriented Programming

- Define protocols to describe capabilities, not implementations.
- Use protocols for dependency injection: inject `UserRepository` (protocol) rather than `ConcreteUserRepository` (type) — enables mocking in tests.
- Use protocol extensions for default implementations — avoids duplicating code across conforming types.
- Use `some Protocol` (opaque return type) to hide concrete types while preserving type safety.
- Use `any Protocol` (existential) only when the concrete type is genuinely unknown at call site — existentials have runtime overhead.

## Naming Idioms

- Types, protocols, enums, cases (capitalized): `PascalCase`.
- Functions, methods, variables, properties: `camelCase`.
- Boolean properties: `isX`, `hasX`, `canX`, `shouldX`.
- Factory methods: `make{Something}()` or static `{Type}({label}:)` style.
- `guard` for early exit — the happy path reads linearly.
- Use `access control` deliberately: `private` for implementation details, `internal` (default) for module use, `public` for package/library APIs.

## Logging

- Use **swift-log** (`apple/swift-log`) — Apple's official server-side logging API with pluggable backends.
- For Apple platforms (iOS/macOS), use **`os.Logger`** (`os` framework) — integrates with Console.app and Instruments with near-zero overhead when logs are not collected.
- Initialize a logger per subsystem:
  ```swift
  // Server-side (swift-log)
  import Logging
  let logger = Logger(label: "com.myapp.orders")

  // Apple platforms (os.Logger)
  import os
  let logger = Logger(subsystem: "com.myapp", category: "orders")
  ```
- Use string interpolation with privacy controls (`os.Logger`) — sensitive data is redacted automatically in production:
  ```swift
  logger.info("Order created: orderId=\(order.id, privacy: .public), userId=\(user.id, privacy: .private)")
  ```
- Use structured metadata with swift-log:
  ```swift
  var logger = Logger(label: "com.myapp.orders")
  logger[metadataKey: "correlationId"] = "\(correlationId)"
  logger.info("Order created", metadata: ["orderId": "\(order.id)"])
  ```
- Never use `print()` or `debugPrint()` for operational logging — they lack levels, metadata, and are stripped inconsistently across build configurations.
- Never log PII (email, name, phone), credentials (tokens, passwords), or financial data. On Apple platforms, use `privacy: .private` for user-identifiable data — it is redacted in production logs but visible during debugging.
- Use `Logger.MetadataValue` for structured values, not string interpolation in metadata keys.

## Anti-Patterns

- **Force-unwrap (`!`) without justification:** Crashes at runtime with an unhelpful message. Use `guard let`, optional chaining, or `??` with a default.
- **`unowned` for safety:** If the referenced object is deallocated before the closure runs, `unowned` crashes. Use `[weak self]` and `guard let self` inside.
- **Stored closures without `[weak self]`:** Creates a retain cycle between the closure and the instance that holds it.
- **`DispatchQueue.main.async` in async code:** Redundant when `@MainActor` is used; creates mixed concurrency models. Standardize on structured concurrency.
- **`class` for all types by default:** Value types (`struct`) are simpler, thread-safe by default, and have no retain cycle risk. Choose `class` intentionally.
- **Singletons for testable services:** Singletons cannot be replaced in tests. Use protocol-based dependency injection.
- **Deeply nested `if let` / `guard let` chains:** More than 3 levels signals the need for refactoring into smaller functions or a different optional-handling strategy.

## Dos
- Use `struct` by default — value types are simpler, thread-safe, and have no retain cycle risk.
- Use `guard let` for early returns — it flattens control flow and makes the happy path clear.
- Use `[weak self]` in stored closures to prevent retain cycles.
- Use `async`/`await` with structured concurrency (`TaskGroup`, `async let`) over GCD.
- Use `@MainActor` for UI-bound code instead of `DispatchQueue.main.async`.
- Use protocols for dependency injection and testability — not singletons.
- Use SPM (Swift Package Manager) over CocoaPods for dependency management.

## Don'ts
- Don't force-unwrap (`!`) without strong justification — it crashes at runtime with unhelpful messages.
- Don't use `unowned` when the lifecycle isn't guaranteed — it crashes on deallocation; prefer `weak`.
- Don't use `class` by default — choose it intentionally when reference semantics are needed.
- Don't use singletons for testable services — they can't be replaced in unit tests.
- Don't use `DispatchQueue.main.async` in `@MainActor` code — it creates mixed concurrency models.
- Don't nest more than 3 `if let` / `guard let` — refactor into smaller functions.
- Don't use `Any` or `AnyObject` without type narrowing — it defeats the type system.
- Don't write ObjC-style delegate pattern when Combine or async/await fits the use case.
- Don't use `@objc` unless Objective-C interop is genuinely required.
- Don't create `Manager`/`Helper` classes — use value types and protocols.
