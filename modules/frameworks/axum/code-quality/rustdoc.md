# Axum + rustdoc

> Extends `modules/code-quality/rustdoc.md` with Axum-specific integration.
> Generic rustdoc conventions (doc comment format, doc tests, CI integration) are NOT repeated here.

## Integration Setup

Enforce doc coverage for public handler and extractor types. Add rustdoc lints to `Cargo.toml`:

```toml
[lints.rustdoc]
broken_intra_doc_links = "deny"
private_intra_doc_links = "deny"
missing_crate_level_docs = "warn"
```

```yaml
# .github/workflows/docs.yml
- name: Check docs build
  run: |
    RUSTDOCFLAGS="-D warnings -D rustdoc::broken_intra_doc_links" \
      cargo doc --no-deps --all-features

- name: Run doc tests
  run: cargo test --doc --all-features
```

## Framework-Specific Patterns

### Documenting Handler Functions

Axum handler functions are the primary API contract. Document each with its HTTP method, path, extractor requirements, success/error responses, and authentication requirements:

```rust
/// Lists all active users in the system.
///
/// # Route
///
/// `GET /api/v1/users`
///
/// # Authentication
///
/// Requires a valid Bearer token in the `Authorization` header.
/// The token must have the `users:read` scope.
///
/// # Query Parameters
///
/// - `page` — page number (1-indexed, default: 1)
/// - `per_page` — results per page (1–100, default: 20)
///
/// # Responses
///
/// - `200 OK` — [`UserListResponse`] paginated user list
/// - `400 Bad Request` — invalid query parameter format
/// - `401 Unauthorized` — missing or invalid Bearer token
/// - `403 Forbidden` — token lacks `users:read` scope
///
/// # Example
///
/// ```no_run
/// // GET /api/v1/users?page=2&per_page=10
/// // Authorization: Bearer <token>
/// ```
pub async fn list_users(
    State(state): State<Arc<AppState>>,
    Query(params): Query<ListUsersParams>,
) -> Result<Json<UserListResponse>, AppError> {
```

### Documenting Route Groups with doc test Examples

Document the route registration function with example request/response patterns. Use `no_run` for examples that require a running server:

```rust
/// Builds and returns the user-management sub-router.
///
/// Routes registered:
/// - `GET    /users`        — [`list_users`]
/// - `POST   /users`        — [`create_user`]
/// - `GET    /users/:id`    — [`get_user`]
/// - `PUT    /users/:id`    — [`update_user`]
/// - `DELETE /users/:id`    — [`delete_user`]
///
/// All routes require authentication via [`AuthLayer`].
///
/// # Example
///
/// ```no_run
/// use axum::Router;
/// use std::sync::Arc;
///
/// let state = Arc::new(AppState::new());
/// let router = Router::new()
///     .merge(user_routes())
///     .with_state(state);
/// ```
pub fn user_routes() -> Router<Arc<AppState>> {
```

### Documenting Custom Extractors

Custom extractors implementing `FromRequestParts` or `FromRequest` must document their rejection conditions — these are the "error cases" that callers cannot see from the type signature alone:

```rust
/// An authenticated user extracted from the `Authorization` header.
///
/// Implements [`FromRequestParts`] — can be used as a handler parameter
/// alongside other extractors without consuming the request body.
///
/// # Rejection
///
/// Returns [`AppError::Unauthorized`] (HTTP 401) if:
/// - The `Authorization` header is missing
/// - The token format is not `Bearer <token>`
/// - The token signature is invalid or expired
///
/// # Example
///
/// ```no_run
/// async fn protected_handler(
///     AuthenticatedUser(user): AuthenticatedUser,
///     State(state): State<Arc<AppState>>,
/// ) -> Result<Json<UserResponse>, AppError> {
///     Ok(Json(UserResponse::from(user)))
/// }
/// ```
pub struct AuthenticatedUser(pub User);
```

### Documenting AppState

`AppState` is the central dependency injection container in Axum. Document each field's purpose and its thread-safety guarantees:

```rust
/// Shared application state injected into all handlers via [`State`].
///
/// All fields must be `Clone + Send + Sync + 'static` to satisfy Axum's
/// [`Handler`] trait bounds. Use [`Arc`] for heap-allocated resources.
///
/// # Fields
///
/// - `db` — PostgreSQL connection pool (max 20 connections)
/// - `redis` — Redis connection pool for caching and session storage
/// - `config` — immutable application configuration loaded at startup
pub struct AppState {
```

## Additional Dos

- Document all custom extractors with their rejection conditions — these are invisible to callers from the type system alone.
- Add `// Route:` and authentication requirements to every public handler — they serve as inline API reference without requiring a Swagger UI.
- Use `no_run` in doc test examples that require a running server or database — prevents false failures in `cargo test --doc`.

## Additional Don'ts

- Don't leave `AppError` variants undocumented — each variant's HTTP status code mapping and trigger condition must be described for API consumers.
- Don't use `cargo doc` without `--all-features` for Axum projects — feature-gated extractors (multipart, WebSocket) won't appear in the generated docs.
- Don't skip doc tests for helper functions used across many handlers — they verify the helper's API contract and catch signature changes that break callers.
