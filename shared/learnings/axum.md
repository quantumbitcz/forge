# Cross-Project Learnings: axum

## PREEMPT items

### AX-PREEMPT-001: Extractor order matters — body-consuming extractors must be last
- **Domain:** routing
- **Pattern:** `Json<T>` consumes the request body. If placed before `State<T>` or `Path<T>` in the handler signature, extraction fails silently or panics. Body-consuming extractors must always be the last parameter.
- **Confidence:** HIGH
- **Hit count:** 0

### AX-PREEMPT-002: Handler return type must implement IntoResponse or compilation succeeds but runtime panics
- **Domain:** error-handling
- **Pattern:** Returning `Result<T, E>` where `E` does not implement `IntoResponse` compiles (because of blanket impls) but produces opaque 500 errors at runtime. Always implement `IntoResponse` for custom error types with explicit status code mapping.
- **Confidence:** HIGH
- **Hit count:** 0

### AX-PREEMPT-003: Forgetting Clone on AppState prevents Router compilation
- **Domain:** build
- **Pattern:** Axum requires `State<T>` to be `Clone`. If `AppState` holds non-Clone fields (e.g., a raw connection pool without Arc), the router fails to compile with cryptic trait bound errors. Wrap shared resources in `Arc` inside AppState.
- **Confidence:** HIGH
- **Hit count:** 0

### AX-PREEMPT-004: CPU-bound work on Tokio runtime blocks all async handlers
- **Domain:** concurrency
- **Pattern:** Running CPU-intensive operations (hashing, compression, serialization of large payloads) directly in an async handler starves the Tokio runtime. Use `tokio::task::spawn_blocking` for CPU-heavy work to avoid blocking the event loop.
- **Confidence:** HIGH
- **Hit count:** 0

### AX-PREEMPT-005: SQLx compile-time query checking requires running database
- **Domain:** build
- **Pattern:** `sqlx::query!` and `sqlx::query_as!` macros connect to the database at compile time. CI builds fail without a running database or a prepared `sqlx-data.json` / `.sqlx/` directory. Use `cargo sqlx prepare` to generate offline query metadata.
- **Confidence:** HIGH
- **Hit count:** 0

### AX-PREEMPT-006: Tower middleware layer ordering affects behavior
- **Domain:** middleware
- **Pattern:** Tower layers wrap the inner service — the outermost layer runs first on request and last on response. Placing TraceLayer inside CorsLayer means CORS headers are not logged. Add tracing as the outermost layer, CORS next, then auth.
- **Confidence:** MEDIUM
- **Hit count:** 0

### AX-PREEMPT-007: Serde rename_all on request DTOs must match client convention
- **Domain:** serialization
- **Pattern:** Using `#[serde(rename_all = "camelCase")]` on request DTOs but receiving `snake_case` JSON from the client causes silent deserialization failures (fields default to None or zero). Ensure serde naming matches the API contract.
- **Confidence:** MEDIUM
- **Hit count:** 0
