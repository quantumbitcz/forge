---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "gn-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.744531Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["middleware", "gin"]
    source: "cross-project"
    archived: false
    body_ref: "gn-preempt-001"
  - id: "gn-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.744531Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["request-handling", "gin"]
    source: "cross-project"
    archived: false
    body_ref: "gn-preempt-002"
  - id: "gn-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.744531Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["middleware", "gin"]
    source: "cross-project"
    archived: false
    body_ref: "gn-preempt-003"
  - id: "gn-preempt-004"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.744531Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["api-design", "gin"]
    source: "cross-project"
    archived: false
    body_ref: "gn-preempt-004"
  - id: "gn-preempt-005"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.744531Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["middleware", "gin"]
    source: "cross-project"
    archived: false
    body_ref: "gn-preempt-005"
  - id: "gn-preempt-006"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.744531Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "gin"]
    source: "cross-project"
    archived: false
    body_ref: "gn-preempt-006"
  - id: "gn-preempt-007"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.744531Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["deployment", "gin"]
    source: "cross-project"
    archived: false
    body_ref: "gn-preempt-007"
---
# Cross-Project Learnings: gin

## PREEMPT items

### GN-PREEMPT-001: gin.Default() includes uncontrollable global logger and recovery
<a id="gn-preempt-001"></a>
- **Domain:** middleware
- **Pattern:** `gin.Default()` registers a global logger and recovery middleware that cannot be customized. Use `gin.New()` and register explicit middleware for logging and recovery to control format, output, and error handling.
- **Confidence:** HIGH
- **Hit count:** 0

### GN-PREEMPT-002: c.Bind() aborts on error — use c.ShouldBindJSON() instead
<a id="gn-preempt-002"></a>
- **Domain:** request-handling
- **Pattern:** `c.Bind()` and `c.BindJSON()` call `c.AbortWithError(400, err)` internally on validation failure, bypassing custom error handling. Always use `c.ShouldBindJSON()` which returns the error for manual handling.
- **Confidence:** HIGH
- **Hit count:** 0

### GN-PREEMPT-003: Missing c.Abort() after error response continues handler chain
<a id="gn-preempt-003"></a>
- **Domain:** middleware
- **Pattern:** In middleware, calling `c.JSON(401, ...)` without `c.Abort()` does not stop the handler chain — subsequent handlers still execute. Always use `c.AbortWithStatusJSON()` or call `c.Abort()` after writing the error response.
- **Confidence:** HIGH
- **Hit count:** 0

### GN-PREEMPT-004: gin.H{} for repeated response shapes bypasses type safety
<a id="gn-preempt-004"></a>
- **Domain:** api-design
- **Pattern:** Using `gin.H{"user": user, "count": count}` for response bodies provides no compile-time type safety and makes API contract changes invisible. Define typed response structs with JSON tags for all endpoints.
- **Confidence:** MEDIUM
- **Hit count:** 0

### GN-PREEMPT-005: Context values set with c.Set() are not type-safe
<a id="gn-preempt-005"></a>
- **Domain:** middleware
- **Pattern:** `c.Set("userID", id)` stores values as `interface{}`, requiring type assertion on retrieval with `c.Get("userID")`. Typos in key strings or wrong type assertions cause runtime panics. Use typed helper functions that wrap Set/Get with compile-time safety.
- **Confidence:** MEDIUM
- **Hit count:** 0

### GN-PREEMPT-006: Missing context.Context propagation to database calls
<a id="gn-preempt-006"></a>
- **Domain:** concurrency
- **Pattern:** Using `c.Request.Context()` to propagate cancellation to service and database calls is frequently forgotten. When clients disconnect, queries continue running. Always pass `c.Request.Context()` as the first argument to service methods.
- **Confidence:** HIGH
- **Hit count:** 0

### GN-PREEMPT-007: Graceful shutdown not configured causes dropped requests
<a id="gn-preempt-007"></a>
- **Domain:** deployment
- **Pattern:** Calling `router.Run()` without graceful shutdown causes in-flight requests to be dropped on SIGTERM. Use `http.Server` with `Shutdown(ctx)` and a 30-second drain timeout to allow connections to complete before exit.
- **Confidence:** HIGH
- **Hit count:** 0
