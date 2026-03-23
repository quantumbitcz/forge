# Axum Framework Conventions

> Framework-specific conventions for Axum projects. Language idioms are in `modules/languages/rust.md`. Generic testing patterns are in `modules/testing/rust-test.md`.

## Architecture (Handler / Service / Model)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `handler/` | Axum handler functions, extractors, response building | services (via shared state) |
| `service/` | Business logic, orchestration, validation | repositories / database |
| `model/` | Domain types, database models (SQLx), DTOs | serde, sqlx |
| `middleware/` | Tower middleware: auth, logging, CORS | tower, axum |
| `error/` | Error types with IntoResponse implementations | thiserror, axum |
| `bin/` | App entry point, router construction, state wiring | all modules |

**Dependency rule:** Handlers receive services through shared application state (`Arc<AppState>`). Handlers never access database pools directly.

## Handler Functions

- Handlers are plain `async fn` that take extractors as parameters
- Use typed extractors: `Path<T>`, `Query<T>`, `Json<T>`, `State<T>`
- Return `Result<impl IntoResponse, AppError>` for consistent error handling
- Keep handlers thin -- delegate to services for business logic

## Extractors

- `State(Arc<AppState>)` -- shared application state (DB pool, services)
- `Path<T>` -- URL path parameters
- `Query<T>` -- query string parameters
- `Json<T>` -- request body deserialization (T: DeserializeOwned)
- `Extension<T>` -- request-scoped data from middleware
- Custom extractors implement `FromRequestParts` or `FromRequest`

## Shared State with Arc

- Application state held in `Arc<AppState>` struct
- Services constructed at startup, stored in AppState
- Database pool (`sqlx::PgPool`) shared via AppState
- Never use global mutable state or lazy_static for runtime data

## Tower Middleware

- Use Tower layers for cross-cutting concerns
- `tower_http::cors::CorsLayer` for CORS
- `tower_http::trace::TraceLayer` for request tracing
- Custom middleware as Tower services or `middleware::from_fn`
- Order matters: outermost layer runs first

## Error Handling

- Define `AppError` enum with `thiserror::Error` derive
- Implement `IntoResponse` for `AppError` to map to HTTP status codes
- Use `?` operator throughout -- handlers return `Result<_, AppError>`
- Never use `.unwrap()` or `.expect()` in handlers

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
- All DB operations are async -- no blocking calls

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

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels
- Doc comments (`///`) on all public types and functions
- No `.unwrap()` / `.expect()` in non-test code -- use `?`
- `cargo fmt` enforced, `cargo clippy` with no warnings

## Serde

- `#[derive(Serialize, Deserialize)]` on all DTOs
- Use `#[serde(rename_all = "camelCase")]` for JSON API responses
- `#[serde(skip_serializing_if = "Option::is_none")]` for optional fields
- Separate request and response types -- never reuse DB models as API types

## Security

- Validate all input at handler boundary via extractors + serde validation
- Parameterized queries only -- SQLx enforces this by design
- JWT validation via middleware layer
- CORS configured restrictively in production
- Secrets from environment variables via `dotenvy`

## Performance

- Use `tokio::spawn` for truly independent tasks
- Use `tokio::select!` for racing futures
- Use `CancellationToken` for graceful shutdown
- CPU-heavy work goes to `tokio::task::spawn_blocking`

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Dos and Don'ts

### Do
- Use `thiserror` for library errors, `anyhow` for application errors
- Use `?` operator consistently for error propagation
- Use `tracing` crate for structured logging
- Write property-based tests with `proptest` for parsing/serialization logic

### Don't
- Don't use `.unwrap()` in production code -- use `?` or `.expect("reason")`
- Don't use `unsafe` unless you can prove correctness
- Don't clone to satisfy the borrow checker -- refactor ownership instead
- Don't use `Box<dyn Error>` -- use concrete error enums
- Don't ignore compiler warnings -- `#![deny(warnings)]` in CI
