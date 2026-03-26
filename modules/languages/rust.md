# Rust Language Conventions

## Ownership and Borrowing

- Rust's ownership system enforces memory safety at compile time — understand moves, borrows, and lifetimes before fighting the borrow checker.
- **Move semantics by default:** assigning or passing a non-`Copy` type transfers ownership. Use references (`&T`, `&mut T`) to borrow without moving.
- Functions should accept `&T` (shared reference) or `&mut T` (exclusive reference) rather than consuming `T` unless ownership is genuinely required.
- Use `&str` for string parameters (borrowed), `String` for owned string data. Do not convert between them unnecessarily.
- If you find yourself calling `.clone()` everywhere, the ownership model needs redesign — restructure to use references or `Arc`.

## Lifetimes

- Most lifetimes are inferred — add explicit lifetime annotations only when the compiler requires them.
- If a function has 3+ lifetime parameters, consider restructuring: the data often should be owned, not borrowed across complex boundaries.
- `'static` lifetime means the value can live for the entire program — not a shortcut to avoid lifetime reasoning.

## Traits

- Use `trait` for shared behavior, similar to interfaces. Implement `Display`, `Debug`, `Clone`, `From`/`Into` as appropriate.
- Implement `From<T>` (not `Into<T>`) — the blanket impl provides `Into` automatically.
- Use `impl Trait` in function signatures for simple generic bounds; use `<T: Trait>` when the type parameter is referenced multiple times.
- `dyn Trait` for trait objects (runtime dispatch) — avoid in hot paths due to vtable overhead; prefer generics for compile-time dispatch.
- Do not use `Box<dyn Error>` as an error type in libraries — use concrete error enums. `Box<dyn Error>` is acceptable in application `main`.

## Error Handling

- Use `Result<T, E>` for operations that can fail — not panics, not `Option` for errors.
- Use `Option<T>` for values that are legitimately absent (not errors).
- Propagate errors with `?` — it converts the error type via `From` and returns early.
- Never use `.unwrap()` or `.expect()` in production code — use `?`, handle with `match`, or provide a meaningful `expect("invariant description")` in tests.
- Use `thiserror` for defining library error enums with `#[derive(thiserror::Error)]`.
- Use `anyhow` for application-level error handling where error type erasure is acceptable.
- Define an `AppError` enum covering all domain failure modes; implement `IntoResponse` (or equivalent) to map to HTTP status codes.

## Memory Management

- Rust has no garbage collector — memory is managed via ownership and RAII (destructors via `Drop`).
- Stack allocation is preferred; heap allocation via `Box<T>`, `Vec<T>`, `String`, `Arc<T>`, etc.
- `Arc<T>` for shared ownership across threads (thread-safe reference counting).
- `Arc<Mutex<T>>` or `Arc<RwLock<T>>` when shared state also requires mutation.
- Do not use `Rc<T>` / `RefCell<T>` in multi-threaded contexts — they are not `Send`/`Sync`.
- `unsafe` is opt-in and must be justified with a comment explaining the safety invariant being upheld.

## Concurrency

- Rust's type system enforces thread safety at compile time via `Send` and `Sync` traits.
- Use `tokio` (or `async-std`) for async I/O; never block the async runtime with synchronous I/O or `std::thread::sleep`.
- Use `tokio::spawn` for truly independent background tasks.
- Use `tokio::select!` to race futures — first-to-complete wins, others are dropped.
- CPU-heavy work goes to `tokio::task::spawn_blocking` to avoid blocking the async runtime.
- Use `CancellationToken` (from `tokio-util`) for graceful shutdown of long-running tasks.

## Naming Idioms

- Types, traits, enums, and variants: `PascalCase`.
- Functions, methods, variables, modules: `snake_case`.
- Constants and statics: `UPPER_SNAKE_CASE`.
- Modules: `snake_case` file names, matching the `mod` declaration.
- Conversion methods: `to_xxx()` (borrows, cheap), `into_xxx()` (consumes, potentially allocating), `as_xxx()` (cheap reference cast).
- Builder pattern: `XxxBuilder` with fluent `.with_field(value)` methods, `.build() -> Result<Xxx>`.

## Anti-Patterns

- **Clone-happy code:** Calling `.clone()` everywhere indicates wrong ownership structure. Redesign with references or `Arc`.
- **`.unwrap()` / `.expect("")` in production paths:** Panics at runtime. Use `?` or explicit error handling.
- **`unsafe` without documented invariants:** Every `unsafe` block needs a comment proving the safety requirement is met.
- **Fighting the borrow checker with workarounds:** `unsafe`, excessive cloning, or `RefCell` everywhere usually mean the data model needs rethinking, not that the compiler is wrong.
- **`std::thread::sleep` in async context:** Blocks the worker thread. Use `tokio::time::sleep`.
- **Lifetime annotation explosion:** 3+ explicit lifetimes in one signature is a design smell — consider owned types.
- **`Box<dyn Error>` in library APIs:** Loses error type information. Use typed error enums with `thiserror`.
- **Ignoring `#![deny(warnings)]`:** Rust compiler warnings are almost always correct. Fix them rather than suppress.

## Dos
- Use `?` operator for error propagation — clean, composable, and the idiomatic Rust pattern.
- Use `enum` with `thiserror` for typed error hierarchies in libraries.
- Use `clippy` in CI (`cargo clippy -- -D warnings`) — it catches idiomatic issues the compiler doesn't.
- Use `impl Into<T>` / `impl AsRef<T>` for flexible function parameters.
- Use `#[derive(...)]` for `Debug`, `Clone`, `PartialEq` — don't implement manually unless necessary.
- Use `Arc<Mutex<T>>` for shared mutable state across threads — prefer `tokio::sync::Mutex` in async.
- Use `cargo fmt` for consistent formatting — no style debates needed.

## Don'ts
- Don't use `.unwrap()` in production code — it panics on `None`/`Err`; use `?` or explicit matching.
- Don't use `unsafe` without a documented safety invariant — every `unsafe` block needs a comment proving correctness.
- Don't fight the borrow checker with excessive `.clone()` — redesign data ownership instead.
- Don't use `std::thread::sleep` in async contexts — use `tokio::time::sleep`.
- Don't use `Box<dyn Error>` in library APIs — use typed error enums for downstream matching.
- Don't suppress compiler warnings — Rust warnings are almost always correct and actionable.
- Don't use `String` when `&str` suffices — avoid unnecessary heap allocations.
