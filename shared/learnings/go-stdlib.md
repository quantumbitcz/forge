---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "gs-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.746479Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "go", "stdlib"]
    source: "cross-project"
    archived: false
    body_ref: "gs-preempt-001"
  - id: "gs-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.746479Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "go", "stdlib"]
    source: "cross-project"
    archived: false
    body_ref: "gs-preempt-002"
  - id: "gs-preempt-003"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.746479Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["error-handling", "go", "stdlib"]
    source: "cross-project"
    archived: false
    body_ref: "gs-preempt-003"
  - id: "gs-preempt-004"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.746479Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["routing", "go", "stdlib"]
    source: "cross-project"
    archived: false
    body_ref: "gs-preempt-004"
  - id: "gs-preempt-005"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.746479Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["resource-management", "go", "stdlib"]
    source: "cross-project"
    archived: false
    body_ref: "gs-preempt-005"
  - id: "gs-preempt-006"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.746479Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["architecture", "go", "stdlib"]
    source: "cross-project"
    archived: false
    body_ref: "gs-preempt-006"
  - id: "gs-preempt-007"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.746479Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["serialization", "go", "stdlib"]
    source: "cross-project"
    archived: false
    body_ref: "gs-preempt-007"
---
# Cross-Project Learnings: go-stdlib

## PREEMPT items

### GS-PREEMPT-001: Goroutine leak from missing context cancellation
<a id="gs-preempt-001"></a>
- **Domain:** concurrency
- **Pattern:** Launching goroutines without passing a cancellable `context.Context` causes them to outlive the request. Over time, leaked goroutines accumulate and exhaust memory. Always pass `ctx` and select on `ctx.Done()` in long-running goroutines. Detect leaks with `goleak` in tests.
- **Confidence:** HIGH
- **Hit count:** 0

### GS-PREEMPT-002: Concurrent map read/write causes fatal runtime panic
<a id="gs-preempt-002"></a>
- **Domain:** concurrency
- **Pattern:** Go maps are not thread-safe. Concurrent reads and writes from multiple goroutines cause a non-recoverable `fatal error: concurrent map read and map write`. Use `sync.RWMutex` to protect maps or `sync.Map` for simple key-value patterns. Run tests with `-race`.
- **Confidence:** HIGH
- **Hit count:** 0

### GS-PREEMPT-003: Error wrapping with %w breaks errors.Is() chain if wrapping twice
<a id="gs-preempt-003"></a>
- **Domain:** error-handling
- **Pattern:** Wrapping errors with `fmt.Errorf("outer: %w", fmt.Errorf("inner: %w", sentinel))` works, but custom error types that embed an error field AND use `%w` can create confusing chains. Keep one wrapping mechanism per error type — either `%w` or custom `Unwrap()`.
- **Confidence:** MEDIUM
- **Hit count:** 0

### GS-PREEMPT-004: http.ServeMux pattern matching changed in Go 1.22
<a id="gs-preempt-004"></a>
- **Domain:** routing
- **Pattern:** Go 1.22 introduced method-aware routing (`GET /users/{id}`) in `http.ServeMux`. Code targeting Go 1.21 and below must use a third-party router or manual method checking. Ensure `go.mod` minimum version matches the routing pattern used.
- **Confidence:** HIGH
- **Hit count:** 0

### GS-PREEMPT-005: defer runs at function return, not block scope
<a id="gs-preempt-005"></a>
- **Domain:** resource-management
- **Pattern:** `defer` inside a loop defers cleanup to function return, not loop iteration end. Opening resources (files, connections) in a loop with defer causes resource exhaustion. Extract loop bodies to helper functions or use explicit close at loop end.
- **Confidence:** HIGH
- **Hit count:** 0

### GS-PREEMPT-006: init() functions create hidden initialization coupling
<a id="gs-preempt-006"></a>
- **Domain:** architecture
- **Pattern:** `init()` functions run before `main()` in import order, creating hidden startup dependencies that are hard to test and debug. Prefer explicit initialization in `main()` with dependency injection. Reserve `init()` for registering drivers or codecs only.
- **Confidence:** MEDIUM
- **Hit count:** 0

### GS-PREEMPT-007: JSON struct tags missing cause silent field name mismatches
<a id="gs-preempt-007"></a>
- **Domain:** serialization
- **Pattern:** Go's `encoding/json` uses field names verbatim (PascalCase) when `json:` tags are missing. APIs expecting `camelCase` receive wrong field names and clients silently ignore them. Always add `json:"fieldName"` tags on all serialized struct fields.
- **Confidence:** HIGH
- **Hit count:** 0
