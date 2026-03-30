# Axum + clippy

> Extends `modules/code-quality/clippy.md` with Axum-specific integration.
> Generic clippy conventions (lint groups, configuration, CI integration) are NOT repeated here.

## Integration Setup

Run clippy with all features and targets — Axum projects commonly use feature-gated extractors and middleware:

```yaml
# .github/workflows/quality.yml
- name: Run Clippy
  run: cargo clippy --workspace --all-targets --all-features -- -D warnings
```

Configure workspace-level lint settings in `Cargo.toml`:

```toml
[workspace.lints.clippy]
pedantic = "warn"
nursery = "warn"
# Allow noisy pedantic lints common in Axum handler signatures
module_name_repetitions = "allow"
must_use_candidate = "allow"
missing_errors_doc = "warn"   # handlers returning Result must document errors

[workspace.lints.rust]
unsafe_code = "forbid"
```

## Framework-Specific Patterns

### unused_async for Handler Functions

Axum requires all handlers to be `async fn` (matched by the `Handler` trait bounds), but handlers that do not perform any async operations trigger `clippy::unused_async`. Suppress with justification or refactor to use a sync helper:

```rust
// Clippy flags this if no .await is present
async fn health_check() -> StatusCode {
    StatusCode::OK
}

// Suppress when the async signature is required by Axum's routing
#[allow(clippy::unused_async)]  // required by axum::Handler trait bounds
async fn health_check() -> StatusCode {
    StatusCode::OK
}
```

A better fix: extract sync logic into a non-async helper and keep the handler as a thin async wrapper.

### Send + Sync Bounds on AppState

Axum's `State` extractor requires `AppState: Clone + Send + Sync + 'static`. Clippy's `clippy::redundant_clone` and `clippy::arc_with_non_send_sync` lints help identify state types that may not satisfy these bounds at compile time:

```rust
// clippy::arc_with_non_send_sync flags this if InnerState is !Send
let state = Arc::new(InnerState {
    db: Rc::new(pool), // Rc is !Send — flagged
});

// Fix: use Arc<Pool> not Rc<Pool>
let state = Arc::new(AppState {
    db: Arc::new(pool),
});
```

### Tower Middleware and clippy::type_complexity

Tower middleware types can be deeply nested generics. `clippy::type_complexity` fires on large `ServiceBuilder` chains stored in type aliases or function return positions. Use type aliases to suppress at the definition site:

```rust
// Suppress type_complexity for Tower service stacks
#[allow(clippy::type_complexity)]
pub fn build_middleware_stack(
    app: Router,
) -> Router<Arc<AppState>> {
    app.layer(
        ServiceBuilder::new()
            .layer(TraceLayer::new_for_http())
            .layer(CorsLayer::permissive())
            .layer(CompressionLayer::new()),
    )
}
```

Or define a named type alias:

```rust
type AppMiddleware = Stack<
    TraceLayer<SharedClassifier<ServerErrorsAsFailures>>,
    Stack<CorsLayer, Identity>,
>;
```

### clippy::wildcard_imports in Handler Modules

Handler modules often import from `axum::extract::*` and `axum::http::*`. `clippy::pedantic` includes `wildcard_imports` — suppress it for Axum import blocks where the wildcard is idiomatic:

```rust
#[allow(clippy::wildcard_imports)]
use axum::{
    extract::*,
    http::StatusCode,
    response::IntoResponse,
    Json,
};
```

Prefer explicit imports in new code but allow wildcards in generated or template files.

### Error Type IntoResponse Implementations

Axum's error handling requires custom error types to implement `IntoResponse`. Clippy's `clippy::match_wildcard_for_single_variants` and `clippy::match_same_arms` apply to the `match` arms in `IntoResponse`:

```rust
impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            AppError::NotFound(msg) => (StatusCode::NOT_FOUND, msg),
            AppError::Unauthorized => (StatusCode::UNAUTHORIZED, "unauthorized".to_string()),
            AppError::Internal(e) => {
                tracing::error!("internal error: {:?}", e);
                (StatusCode::INTERNAL_SERVER_ERROR, "internal server error".to_string())
            }
        };
        (status, Json(json!({ "error": message }))).into_response()
    }
}
```

## Additional Dos

- Enable `clippy::missing_errors_doc` as warn for handlers and service functions returning `Result` — callers need to know which error variants to expect.
- Suppress `clippy::unused_async` per handler with a comment — it documents the intentional async signature required by Axum's trait bounds.
- Run `cargo clippy --all-features` — feature-gated extractors (e.g., `multipart`, `ws`) may only be analyzed under their respective feature flags.

## Additional Don'ts

- Don't suppress `clippy::arc_with_non_send_sync` — it protects against `AppState` types that compile in single-threaded tests but panic in multi-threaded Axum servers.
- Don't add `#![allow(clippy::pedantic)]` at the crate level — suppress individual noisy lints with `= "allow"` in `Cargo.toml` so the suppression is visible and reviewable.
- Don't ignore `clippy::perf` lints in extractors — unnecessary clones in high-throughput handlers have measurable latency impact under load.
