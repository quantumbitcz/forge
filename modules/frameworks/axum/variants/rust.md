# Axum + Rust Variant

> Rust-specific patterns for Axum projects. Extends `modules/languages/rust.md` and `modules/frameworks/axum/conventions.md`.

## Ownership Anti-Patterns

- **Clone-happy code:** If you find yourself `.clone()`ing everywhere, the ownership model is wrong. Refactor to use references or Arc.
- **Lifetime annotation explosion:** If a function has 3+ lifetime parameters, consider restructuring. Often means data should be owned, not borrowed.
- **String ownership confusion:** Use `&str` for function parameters, `String` for owned data. Don't convert unnecessarily.

## Tokio Patterns

- Use `tokio::spawn` for truly independent tasks, not for simple async composition
- Use `tokio::select!` for racing futures (first-to-complete wins)
- Use `CancellationToken` for graceful shutdown of long-running tasks
- Set `worker_threads` explicitly in production -- don't rely on defaults
- Never block the async runtime: no `std::thread::sleep`, no blocking file I/O

## Async / Tokio

- All I/O operations are async
- Use `tokio::spawn` for background tasks
- Use `tokio::select!` for concurrent operations with cancellation
- CPU-heavy work goes to `tokio::task::spawn_blocking`

## Type Design

- Use `#[derive(Clone)]` only when types genuinely need cloning -- prefer references
- Use `Arc<T>` for shared read-only state, `Arc<Mutex<T>>` only when mutation is required
- Prefer strong types over primitive obsession (newtypes for IDs, etc.)
- No `std::thread::sleep` in async context -- use `tokio::time::sleep`

## Compile-Time Safety

- Use `sqlx::query!` for compile-time SQL checking
- Use `#[derive(Serialize, Deserialize)]` with explicit `#[serde(rename_all)]`
- Leverage the type system to make invalid states unrepresentable
