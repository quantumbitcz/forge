---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "ax-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.702774Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["routing", "axum"]
    source: "cross-project"
    archived: false
    body_ref: "ax-preempt-001"
  - id: "ax-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.702774Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["error-handling", "axum"]
    source: "cross-project"
    archived: false
    body_ref: "ax-preempt-002"
  - id: "ax-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.702774Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["build", "axum"]
    source: "cross-project"
    archived: false
    body_ref: "ax-preempt-003"
  - id: "ax-preempt-004"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.702774Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "axum"]
    source: "cross-project"
    archived: false
    body_ref: "ax-preempt-004"
  - id: "ax-preempt-005"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.702774Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["build", "axum"]
    source: "cross-project"
    archived: false
    body_ref: "ax-preempt-005"
  - id: "ax-preempt-006"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.702774Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["middleware", "axum"]
    source: "cross-project"
    archived: false
    body_ref: "ax-preempt-006"
  - id: "ax-preempt-007"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.702774Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["serialization", "axum"]
    source: "cross-project"
    archived: false
    body_ref: "ax-preempt-007"
---
# Cross-Project Learnings: axum

## PREEMPT items

### AX-PREEMPT-001: Extractor order matters — body-consuming extractors must be last
<a id="ax-preempt-001"></a>
- **Domain:** routing
- **Pattern:** `Json<T>` consumes the request body. If placed before `State<T>` or `Path<T>` in the handler signature, extraction fails silently or panics. Body-consuming extractors must always be the last parameter.
- **Confidence:** HIGH
- **Hit count:** 0

### AX-PREEMPT-002: Handler return type must implement IntoResponse or compilation succeeds but runtime panics
<a id="ax-preempt-002"></a>
- **Domain:** error-handling
- **Pattern:** Returning `Result<T, E>` where `E` does not implement `IntoResponse` compiles (because of blanket impls) but produces opaque 500 errors at runtime. Always implement `IntoResponse` for custom error types with explicit status code mapping.
- **Confidence:** HIGH
- **Hit count:** 0

### AX-PREEMPT-003: Forgetting Clone on AppState prevents Router compilation
<a id="ax-preempt-003"></a>
- **Domain:** build
- **Pattern:** Axum requires `State<T>` to be `Clone`. If `AppState` holds non-Clone fields (e.g., a raw connection pool without Arc), the router fails to compile with cryptic trait bound errors. Wrap shared resources in `Arc` inside AppState.
- **Confidence:** HIGH
- **Hit count:** 0

### AX-PREEMPT-004: CPU-bound work on Tokio runtime blocks all async handlers
<a id="ax-preempt-004"></a>
- **Domain:** concurrency
- **Pattern:** Running CPU-intensive operations (hashing, compression, serialization of large payloads) directly in an async handler starves the Tokio runtime. Use `tokio::task::spawn_blocking` for CPU-heavy work to avoid blocking the event loop.
- **Confidence:** HIGH
- **Hit count:** 0

### AX-PREEMPT-005: SQLx compile-time query checking requires running database
<a id="ax-preempt-005"></a>
- **Domain:** build
- **Pattern:** `sqlx::query!` and `sqlx::query_as!` macros connect to the database at compile time. CI builds fail without a running database or a prepared `sqlx-data.json` / `.sqlx/` directory. Use `cargo sqlx prepare` to generate offline query metadata.
- **Confidence:** HIGH
- **Hit count:** 0

### AX-PREEMPT-006: Tower middleware layer ordering affects behavior
<a id="ax-preempt-006"></a>
- **Domain:** middleware
- **Pattern:** Tower layers wrap the inner service — the outermost layer runs first on request and last on response. Placing TraceLayer inside CorsLayer means CORS headers are not logged. Add tracing as the outermost layer, CORS next, then auth.
- **Confidence:** MEDIUM
- **Hit count:** 0

### AX-PREEMPT-007: Serde rename_all on request DTOs must match client convention
<a id="ax-preempt-007"></a>
- **Domain:** serialization
- **Pattern:** Using `#[serde(rename_all = "camelCase")]` on request DTOs but receiving `snake_case` JSON from the client causes silent deserialization failures (fields default to None or zero). Ensure serde naming matches the API contract.
- **Confidence:** MEDIUM
- **Hit count:** 0
