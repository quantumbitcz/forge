# Axum + rustfmt

> Extends `modules/code-quality/rustfmt.md` with Axum-specific integration.
> Generic rustfmt conventions (installation, configuration options, CI integration) are NOT repeated here.

## Integration Setup

Standard `cargo fmt --all -- --check` applies to Axum projects without modification. Ensure the toolchain is pinned in `rust-toolchain.toml` to prevent formatting drift:

```toml
# rust-toolchain.toml
[toolchain]
channel = "stable"
components = ["rustfmt", "clippy"]
```

```yaml
# .github/workflows/quality.yml
- name: Check formatting
  run: cargo fmt --all -- --check
```

## Framework-Specific Patterns

### Formatting Handler Router Definitions

Axum router definitions with many routes benefit from consistent alignment. `rustfmt` formats method chains vertically when they exceed `max_width`. Use the vertical style consistently — avoid manually breaking lines to force a specific layout:

```rust
// rustfmt will format this consistently regardless of how you write it
let app = Router::new()
    .route("/", get(index))
    .route("/users", get(list_users).post(create_user))
    .route("/users/:id", get(get_user).put(update_user).delete(delete_user))
    .route("/health", get(health_check))
    .with_state(state);
```

Set `max_width = 100` in `rustfmt.toml` — Axum route definitions with path parameters are verbose and 80 characters is too narrow:

```toml
# rustfmt.toml
edition = "2021"
max_width = 100
imports_granularity = "Module"
group_imports = "StdExternalCrate"
```

### Formatting Extractor Parameter Lists

Axum handlers with multiple extractors have long parameter lists. Rustfmt breaks them across lines at `max_width`. Avoid manually formatting these — let rustfmt decide:

```rust
// Let rustfmt format long parameter lists consistently
async fn create_order(
    State(state): State<Arc<AppState>>,
    Path(user_id): Path<Uuid>,
    Query(params): Query<CreateOrderParams>,
    Json(body): Json<CreateOrderRequest>,
) -> Result<impl IntoResponse, AppError> {
```

Do not use `#[rustfmt::skip]` on handler signatures — it prevents consistent formatting across the codebase.

### Struct Initialization for AppState and Request Types

Rustfmt's `use_field_init_shorthand = true` applies to `AppState` construction. Enable it:

```toml
# rustfmt.toml
use_field_init_shorthand = true
```

```rust
// Without shorthand
let state = AppState {
    db: db,
    cache: cache,
    config: config,
};

// With shorthand (enforced by rustfmt)
let state = AppState { db, cache, config };
```

### Formatting Tower Middleware Chains

`ServiceBuilder` chains are verbose. Rustfmt formats them as vertical method chains. Do not manually align middleware layers — it creates diff noise:

```rust
// rustfmt formats ServiceBuilder consistently
let app = Router::new()
    .route("/api/users", get(list_users))
    .layer(
        ServiceBuilder::new()
            .layer(TraceLayer::new_for_http())
            .layer(TimeoutLayer::new(Duration::from_secs(30)))
            .layer(CorsLayer::permissive())
            .layer(CompressionLayer::new()),
    );
```

## Additional Dos

- Set `max_width = 100` in `rustfmt.toml` — Axum extractor types (`State<Arc<AppState>>`, `Path<(Uuid, String)>`) are wide and require more line space than the default 100 allows in context.
- Enable `imports_granularity = "Module"` — Axum projects import from many sub-modules (`axum::extract`, `axum::http`, `axum::response`) and grouped imports reduce visual noise.
- Run `cargo fmt --all` pre-commit to avoid CI formatting failures — Axum projects have many handler files that accumulate style drift quickly.

## Additional Don'ts

- Don't apply `#[rustfmt::skip]` to handler functions to preserve manually formatted parameter lists — let rustfmt manage all handler signatures consistently.
- Don't set `max_width` below 100 for Axum projects — Axum's extractor and response types are inherently verbose; narrow formatting produces hard-to-read one-item-per-line chains.
- Don't use nightly rustfmt options (`unstable_features = true`) without pinning the nightly toolchain version — formatting output can change between nightly releases, causing spurious CI diffs.
