# Axum Documentation Conventions

> Extends `modules/documentation/conventions.md` with Axum-specific patterns.

## Code Documentation

- Use `///` doc comments for all public handler functions, extractors, and state types.
- Router setup: document the route table in the module-level `//!` doc block, not inline.
- Custom extractors (`FromRequest` / `FromRequestParts`): document what they extract, validation rules, and failure modes.
- Shared state (`AppState`): document each field — what it holds, thread-safety contract, and initialization order.
- Error types: document each variant's HTTP mapping and when it is returned.

```rust
/// Creates a new user account.
///
/// Validates email uniqueness before persisting. Returns the created user
/// with a `201 Created` status.
///
/// # Errors
/// - `409 Conflict` — email already registered
/// - `422 Unprocessable Entity` — validation failure (see response body)
pub async fn create_user(
    State(state): State<AppState>,
    Json(payload): Json<CreateUserRequest>,
) -> Result<(StatusCode, Json<UserResponse>), AppError> { ... }
```

## Architecture Documentation

- Document the handler module layout: which routers exist, which state they share.
- Document the `AppState` struct: dependencies, initialization, and any lazy-initialized fields.
- Document the middleware stack (tower layers) in order — tracing, auth, rate limiting, etc.
- OpenAPI: document using `utoipa` crate annotations if used, otherwise maintain an `openapi.yaml` manually.

## Diagram Guidance

- **Middleware stack:** Sequence diagram showing tower layer order for a typical request.
- **State dependencies:** Class diagram for `AppState` and its nested dependency types.

## Dos

- Module-level `//!` doc for router modules listing all routes and their handlers
- Document `AppError` variants exhaustively — they define the API error contract
- Note `Send + Sync + 'static` requirements in state type docs

## Don'ts

- Don't document generated code from `#[derive]` macros
- Don't omit error variant docs — callers need to know when each error fires
