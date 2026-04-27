# Swift Language Conventions
> Support tier: contract-verified
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

Swift 5.5+ structured concurrency. All guidance assumes Swift 5.9+; Swift 6 strict-concurrency specifics called out inline. Use `async`/`await` for all asynchronous work — no completion handlers in new code. Annotate UI-bound types with `@MainActor`; use `actor` for thread-safe mutable state in services. Never reach for `DispatchQueue.main.async` in new code — use `@MainActor` or `await MainActor.run { }`.

### Task basics

- `Task { ... }` creates an unstructured top-level task inheriting actor context + priority.
- `Task.detached { ... }` discards actor + priority inheritance — use only for CPU-bound work that should not touch the UI actor.
- `Task.sleep(for: .seconds(N))` is cancellation-aware; `Thread.sleep` is not.
- `Task.isCancelled` is a poll; `try Task.checkCancellation()` throws `CancellationError`.
- Priorities: `.userInitiated`, `.utility`, `.background`. Avoid `.high` in library code.
- Use `Task { }` to launch async work from synchronous contexts (button actions, lifecycle methods); always hold the handle if the task may need cancellation.

```swift
let task = Task(priority: .userInitiated) {
    try await fetchThumbnail()
}
task.cancel()  // cooperative
```

### TaskGroup and async let

- `async let` is lexically scoped parallelism for a fixed number of child tasks; cancellation propagates automatically.
- `withTaskGroup(of:)` / `withThrowingTaskGroup(of:)` for dynamic fan-out. Always `await group.waitForAll()` or exit the block.
- Prefer `async let` when N is small and known; switch to TaskGroup when N is dynamic or you need early-exit semantics.
- TaskGroup results are unordered — collect into a dictionary keyed by request id if order matters.

```swift
// async let — fixed N
async let a = loadA()
async let b = loadB()
let (x, y) = try await (a, b)

// TaskGroup — dynamic N
try await withThrowingTaskGroup(of: Item.self) { group in
    for id in ids { group.addTask { try await fetch(id) } }
    for try await item in group { items.append(item) }
}
```

### Structured vs unstructured concurrency

- Structured: `async let`, TaskGroup, `async` functions. Parent outlives child; cancellation propagates.
- Unstructured: `Task { }`, `Task.detached`. Caller does not await; leaks possible.
- `Task.detached` is almost never right — forget about it unless you are intentionally breaking out of the actor isolation tree.
- Prefer structured forms inside library code. Unstructured `Task { }` is acceptable at UI boundaries (button handlers, lifecycle hooks) but the handle should still be retained when cancellation matters.
- Cancellation is cooperative: a child task only stops at the next `try Task.checkCancellation()` or cancellation-aware `await` point. CPU loops must poll `Task.isCancelled` themselves.
- Structured tasks inherit task-local values (`@TaskLocal`); detached tasks do not — useful when carrying request-scoped logging context.

```swift
// Structured: parent awaits, cancellation propagates automatically
func loadDashboard() async throws -> Dashboard {
    async let user = fetchUser()
    async let feed = fetchFeed()
    return try await Dashboard(user: user, feed: feed)
}

// Unstructured: caller does not await — store the handle for cancellation
final class FeedViewModel {
    private var refresh: Task<Void, Never>?
    func startRefresh() {
        refresh = Task { await self.reload() }
    }
    func stopRefresh() { refresh?.cancel() }
}
```

### Actor isolation

- `actor` serializes access to mutable state. Calls from outside the actor are always `await`ed.
- Reentrancy: when an actor method awaits, state can change. Never assume invariants hold across `await` boundaries inside an actor.
- `nonisolated` marks read-only or Sendable-safe members.
- `isolated` parameters allow cross-actor escape hatches; prefer structured calls.
- `@MainActor` on a type hoists all members to the main actor; it propagates through protocol conformances.
- Global actors (`@MainActor`, custom `@globalActor`) are the right tool when many types need the same isolation domain.

```swift
actor Counter {
    private var value = 0
    func increment() { value += 1 }
    nonisolated let id: UUID = UUID()  // Sendable immutable — no isolation needed
}
```

### Sendable and data-race safety

- `Sendable` types can cross actor boundaries. Value types with `Sendable` stored properties are `Sendable` automatically.
- `@Sendable` closures may not capture non-Sendable state.
- `@unchecked Sendable` is a promise you are manually enforcing — use only with clear documentation and internal locking.
- Swift 6 strict-concurrency mode promotes Sendable violations from warnings to errors. Region-based isolation (SE-0414) permits more compile-time safe sharing; check compiler diagnostics first before reaching for `@unchecked`.
- Reference types holding mutable state are `Sendable` only if they enforce their own synchronization (lock, dispatch queue, atomic).
- For library APIs targeted at Swift 6, mark protocols `Sendable` early — late retrofits often cascade through every conforming type.

```swift
// Value type — automatically Sendable when all stored properties are Sendable
struct OrderId: Sendable, Hashable { let value: UUID }

// Reference type — opt in only with documented synchronization
final class MetricsCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var hits = 0
    func bump() { lock.withLock { hits += 1 } }
}
```

### AsyncSequence / AsyncStream

- `AsyncSequence` for async iteration; `for try await x in seq`.
- `AsyncStream(unfolding:onCancel:)` bridges a producer callback to an async iterator.
- `AsyncThrowingStream` for producers that can fail.
- Buffering policy matters: `.bufferingNewest(N)` drops old elements; `.unbounded` risks memory growth.
- Always set `continuation.onTermination` to release upstream resources (Combine subscription, file handle, socket).

```swift
let stream = AsyncStream<Event> { continuation in
    let sub = subject.sink { continuation.yield($0) }
    continuation.onTermination = { _ in sub.cancel() }
}
for await event in stream { handle(event) }
```

### Bridging legacy callbacks

- `withCheckedContinuation { cont in ... cont.resume(returning:) }` wraps single-shot callbacks. Must resume exactly once.
- `withCheckedThrowingContinuation` for throwing APIs.
- `withUnsafeContinuation` skips the double-resume check — use only on hot paths after verifying safety.
- Prefer `async`-native APIs when available (URLSession, FileManager).
- Add a `defer { /* cleanup */ }` inside the continuation closure when the legacy API requires teardown on cancellation.

```swift
func load() async throws -> Data {
    try await withCheckedThrowingContinuation { cont in
        legacyLoad { result in
            switch result {
            case .success(let d): cont.resume(returning: d)
            case .failure(let e): cont.resume(throwing: e)
            }
        }
    }
}
```

### Concurrency anti-patterns

- `Task.detached { @MainActor in ... }` to "escape" then re-enter Main — usually indicates an incorrect caller isolation choice.
- Unstructured `Task { }` without holding the handle — leaks; prefer structured or store the handle.
- Assuming actor state invariants hold across `await` — reentrancy will burn you.
- `@unchecked Sendable` without documenting the synchronization mechanism.
- `Task.sleep` used as a retry backoff without cancellation check — never respects `Task.cancel()` semantics if you swallow `CancellationError`.
- Priority inversion: low-priority task holding an actor that a high-priority task awaits. Use `Task.yield()` or restructure.
- Calling `DispatchQueue.main.async` inside `@MainActor` code — redundant and creates two parallel concurrency models.
- Wrapping every legacy callback in `withUnsafeContinuation` to avoid the runtime cost of the checked variant — the diagnostic is worth far more than the nanoseconds saved.

```swift
// BAD: actor reentrancy — `cache` may have changed during `fetch`
actor ImageStore {
    private var cache: [URL: Data] = [:]
    func image(for url: URL) async throws -> Data {
        if let hit = cache[url] { return hit }
        let data = try await network.fetch(url)  // suspension point
        cache[url] = data                        // may overwrite a concurrent write
        return data
    }
}

// GOOD: deduplicate in-flight requests so reentrant calls share one fetch
actor ImageStore {
    private var cache: [URL: Data] = [:]
    private var inflight: [URL: Task<Data, Error>] = [:]
    func image(for url: URL) async throws -> Data {
        if let hit = cache[url] { return hit }
        if let pending = inflight[url] { return try await pending.value }
        let task = Task { try await network.fetch(url) }
        inflight[url] = task
        defer { inflight[url] = nil }
        let data = try await task.value
        cache[url] = data
        return data
    }
}
```

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
- For Apple platforms (iOS/MacOS), use **`os.Logger`** (`os` framework) — integrates with Console.app and Instruments with near-zero overhead when logs are not collected.
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
- PII/credential/financial data logging rules: see `shared/logging-rules.md`. On Apple platforms, use `privacy: .private` for user-identifiable data — redacted in production logs, visible during debugging.
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
- Do use `async let` for fixed-N parallelism; reach for `TaskGroup` only when N is dynamic.
- Do mark read-only immutable actor members `nonisolated`.
- Do resume continuations exactly once; prefer `withCheckedContinuation` / `withCheckedThrowingContinuation` during development.
- Do use `Task.sleep(for:)` over `Thread.sleep` for cancellation-aware backoff.
- Do hold the `Task` handle when an unstructured task may need explicit cancellation.

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
- Don't reach for `Task.detached` to sidestep actor isolation — fix the isolation instead.
- Don't assume state invariants hold across `await` inside an actor (reentrancy).
- Don't mark a type `@unchecked Sendable` without internal synchronization you've documented.
