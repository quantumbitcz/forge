# Axum + Rust Testing Patterns

> Axum-specific testing patterns for Rust. Extends `modules/testing/rust-test.md`.

## Integration Test Setup

- Use `axum::Router` directly in tests with `tower::ServiceExt`
- Build test app with mocked services in AppState
- Use `oneshot` for single-request tests

```rust
use axum::{body::Body, http::Request};
use tower::ServiceExt;

#[tokio::test]
async fn test_get_user() {
    let app = create_test_app().await;
    let response = app
        .oneshot(Request::builder().uri("/users/123").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
}
```

## Database Testing

- Use testcontainers for PostgreSQL in CI
- Run migrations before each test suite
- Use transactions with rollback for test isolation
- Create a `TestDb` helper that provides a pool and cleanup

## Mocking Services

- Define service interfaces as traits
- Use `mockall` crate for auto-generated mocks
- Or use hand-written fakes implementing the trait
- Inject mocks via `Arc<AppState>` in test setup

## Test Organization

- Unit tests: inline `#[cfg(test)] mod tests` with `#[tokio::test]`
- Integration tests: `tests/` directory with shared helpers
- Use parameterized tests via macros for input variations
