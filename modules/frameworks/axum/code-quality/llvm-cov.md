# Axum + llvm-cov

> Extends `modules/code-quality/llvm-cov.md` with Axum-specific integration.
> Generic llvm-cov conventions (installation, LCOV output, CI integration) are NOT repeated here.

## Integration Setup

Use `cargo-llvm-cov` with `nextest` for faster test execution. Exclude Axum infrastructure from coverage thresholds while measuring handler and service logic:

```bash
cargo install cargo-llvm-cov cargo-nextest
rustup component add llvm-tools-preview
```

```yaml
# .github/workflows/coverage.yml
- name: Install cargo-llvm-cov and nextest
  uses: taiki-e/install-action@v2
  with:
    tool: cargo-llvm-cov,cargo-nextest

- name: Run coverage
  run: |
    cargo llvm-cov nextest \
      --workspace \
      --all-features \
      --lcov --output-path coverage.lcov \
      --fail-under-lines 80

- name: Upload to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: coverage.lcov
    fail_ci_if_error: true
```

## Framework-Specific Patterns

### Testing Handlers with axum-test or TestClient

Use `axum_test::TestServer` (or `tower::ServiceExt::oneshot`) to exercise handler code paths:

```rust
use axum::{body::Body, http::{Request, StatusCode}};
use tower::ServiceExt; // for `.oneshot()`

#[tokio::test]
async fn test_get_user_not_found() {
    let app = build_router(mock_state());

    let response = app
        .oneshot(
            Request::builder()
                .uri("/users/nonexistent-id")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}
```

The `oneshot` approach exercises the full handler pipeline including extractors, middleware, and response building — all counted in llvm-cov.

### Excluding Infrastructure Code

Exclude Axum router wiring, `main.rs`, and Tower middleware configuration from coverage thresholds:

```toml
# .cargo/config.toml
[workspace.metadata.llvm-cov]
exclude = [
    "src/main.rs",
    "src/router.rs",    # route registration only
    "src/telemetry.rs", # OpenTelemetry wiring
]
```

```bash
# Or via CLI
cargo llvm-cov nextest \
  --workspace \
  --ignore-filename-regex="(main|router|telemetry)\.rs" \
  --lcov --output-path coverage.lcov
```

### Covering IntoResponse Error Paths

`AppError::into_response()` branches are only covered if tests trigger each error variant. Create handler tests for each error status code:

```rust
#[tokio::test]
async fn test_handler_returns_422_on_validation_failure() {
    let app = build_router(mock_state());
    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/users")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"email": "not-an-email"}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}
```

### Async Coverage for Tokio Tasks

Axum services often spawn background tasks with `tokio::spawn`. These are not automatically covered by request-scoped tests. Test background tasks directly:

```rust
#[tokio::test]
async fn test_background_cleanup_task() {
    let db = setup_test_db().await;
    cleanup_expired_sessions(&db).await.unwrap();
    // assert cleanup occurred
}
```

## Additional Dos

- Use `cargo llvm-cov nextest` — nextest runs Axum integration tests (which require `tokio` runtime) in parallel with better isolation than `cargo test`.
- Set `--fail-under-lines 80` for handler and service packages — Axum request handling code has well-defined branches that are feasible to cover.
- Generate HTML reports locally during development (`cargo llvm-cov --html`) to identify uncovered error paths in `IntoResponse` implementations.

## Additional Don'ts

- Don't include `main.rs` and router wiring in coverage thresholds — they contain no branching logic beyond startup sequencing.
- Don't rely solely on unit tests for Axum handler coverage — middleware processing, extractor rejection paths, and Tower service composition are only exercised through full handler pipeline tests.
- Don't skip coverage for the `AppError` type — every `match` arm in `into_response()` must be covered to ensure all error codes are exercised.
