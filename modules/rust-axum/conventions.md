# Rust/Axum Agent Conventions Reference

> Full details in project CLAUDE.md. This is a curated subset for agent consumption.

## Architecture (Handler / Service / Model)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `handler/` | Axum handler functions, extractors, response building | services (via shared state) |
| `service/` | Business logic, orchestration, validation | repositories / database |
| `model/` | Domain types, database models (SQLx), DTOs | serde, sqlx |
| `middleware/` | Tower middleware: auth, logging, CORS | tower, axum |
| `error/` | Error types with IntoResponse implementations | thiserror, axum |
| `bin/` | Application entry point, router construction, state wiring | all modules |

**Dependency rule:** Handlers receive services through shared application state (`Arc<AppState>`). Handlers never access database pools directly.

## Handler Functions

- Handlers are plain `async fn` that take extractors as parameters
- Use typed extractors: `Path<T>`, `Query<T>`, `Json<T>`, `State<T>`
- Return `Result<impl IntoResponse, AppError>` for consistent error handling
- Keep handlers thin — delegate to services for business logic

```rust
async fn get_user(
    State(state): State<Arc<AppState>>,
    Path(id): Path<Uuid>,
) -> Result<Json<UserResponse>, AppError> {
    let user = state.user_service.find_by_id(id).await?;
    Ok(Json(user.into()))
}
```

## Extractors

- `State(Arc<AppState>)` — shared application state (DB pool, services)
- `Path<T>` — URL path parameters
- `Query<T>` — query string parameters
- `Json<T>` — request body deserialization (T: DeserializeOwned)
- `Extension<T>` — request-scoped data from middleware
- Custom extractors implement `FromRequestParts` or `FromRequest`

## Shared State with Arc

- Application state held in `Arc<AppState>` struct
- Services constructed at startup, stored in AppState
- Database pool (`sqlx::PgPool`) shared via AppState
- Never use global mutable state or lazy_static for runtime data

```rust
struct AppState {
    db: PgPool,
    user_service: UserService,
    config: AppConfig,
}

let state = Arc::new(AppState { db, user_service, config });
let app = Router::new()
    .route("/users/:id", get(get_user))
    .with_state(state);
```

## Tower Middleware

- Use Tower layers for cross-cutting concerns
- `tower_http::cors::CorsLayer` for CORS
- `tower_http::trace::TraceLayer` for request tracing
- Custom middleware as Tower services or Axum `middleware::from_fn`
- Order matters: outermost layer runs first

## Error Handling

- Define `AppError` enum with `thiserror::Error` derive
- Implement `IntoResponse` for `AppError` to map to HTTP status codes
- Use `?` operator throughout — handlers return `Result<_, AppError>`
- Never use `.unwrap()` or `.expect()` in handlers

```rust
#[derive(Debug, thiserror::Error)]
enum AppError {
    #[error("not found: {0}")]
    NotFound(String),
    #[error("validation: {0}")]
    Validation(String),
    #[error("internal: {0}")]
    Internal(#[from] anyhow::Error),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response { /* ... */ }
}
```

| Error Variant | HTTP Status |
|--------------|-------------|
| `NotFound` | 404 |
| `Validation` | 400 |
| `Forbidden` | 403 |
| `Conflict` | 409 |
| `Internal` | 500 |

## SQLx for Database

- Use `sqlx::PgPool` with compile-time query checking (`sqlx::query!` / `sqlx::query_as!`)
- Migrations via `sqlx migrate run` (SQL files in `migrations/`)
- Use transactions via `pool.begin()` for multi-step operations
- All DB operations are async — no blocking calls

## Package Structure

```
src/
  main.rs               # Entry point, router, state wiring
  lib.rs                 # Re-exports, shared types
  handler/               # Axum handler functions
    mod.rs
    {area}.rs
  service/               # Business logic
    mod.rs
    {area}.rs
  model/                 # Domain types, DB models, DTOs
    mod.rs
    {area}.rs
  middleware/             # Tower/Axum middleware
    mod.rs
    auth.rs
  error.rs               # AppError enum + IntoResponse
  config.rs              # Configuration (env, files)
migrations/              # SQLx migration SQL files
  {timestamp}_{description}.sql
```

## Naming Patterns

| Artifact | Pattern | Example |
|----------|---------|---------|
| Handler function | `get_{area}`, `create_{area}` | `get_user`, `create_user` |
| Service | `{Area}Service` | `UserService` |
| Model | `{Area}` (singular) | `User` |
| Create DTO | `Create{Area}` | `CreateUser` |
| Response DTO | `{Area}Response` | `UserResponse` |
| Error type | `AppError` | `AppError::NotFound` |
| Migration | `{timestamp}_{description}.sql` | `20240101_create_users.sql` |
| Test module | `mod tests` (inline) or `tests/` | `#[cfg(test)] mod tests` |

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels
- Doc comments (`///`) on all public types and functions
- No `.unwrap()` / `.expect()` in non-test code — use `?` with proper error types
- No `std::thread::sleep` in async context — use `tokio::time::sleep`
- `cargo fmt` enforced — no manual formatting
- `cargo clippy` must pass with no warnings
- Prefer strong types over primitive obsession (newtypes for IDs, etc.)

## Async / Tokio

- All I/O operations are async
- Never block the async runtime: no `std::thread::sleep`, no blocking file I/O
- Use `tokio::spawn` for background tasks
- Use `tokio::select!` for concurrent operations with cancellation
- CPU-heavy work goes to `tokio::task::spawn_blocking`

## Testing

- **Unit tests:** Inline `#[cfg(test)] mod tests` with `#[tokio::test]`
- **Integration tests:** `tests/` directory with shared test helpers
- **Database tests:** Use testcontainers or a dedicated test database with migrations
- **Mocks:** Use trait objects or `mockall` crate for service mocking
- **Rules:** Test behavior not implementation, one assertion focus per test, use parameterized tests via macros

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn create_user_with_valid_input_succeeds() {
        // arrange, act, assert
    }
}
```

## Security

- Validate all input at handler boundary via extractors + serde validation
- Parameterized queries only — SQLx enforces this by design
- JWT validation via middleware layer
- CORS configured via `CorsLayer` — restrictive origins in production
- Secrets from environment variables via `dotenvy` or config crate

## Serde

- `#[derive(Serialize, Deserialize)]` on all DTOs
- Use `#[serde(rename_all = "camelCase")]` for JSON API responses
- `#[serde(skip_serializing_if = "Option::is_none")]` for optional fields
- Separate request and response types — never reuse DB models as API types

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated files, changing APIs, fixing pre-existing bugs.
