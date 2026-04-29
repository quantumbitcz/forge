---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "an-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.701020Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["dependency-injection", "aspnet"]
    source: "cross-project"
    archived: false
    body_ref: "an-preempt-001"
  - id: "an-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.701020Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "aspnet"]
    source: "cross-project"
    archived: false
    body_ref: "an-preempt-002"
  - id: "an-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.701020Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["persistence", "aspnet"]
    source: "cross-project"
    archived: false
    body_ref: "an-preempt-003"
  - id: "an-preempt-004"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.701020Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["error-handling", "aspnet"]
    source: "cross-project"
    archived: false
    body_ref: "an-preempt-004"
  - id: "an-preempt-005"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.701020Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "aspnet"]
    source: "cross-project"
    archived: false
    body_ref: "an-preempt-005"
  - id: "an-preempt-006"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.701020Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "aspnet"]
    source: "cross-project"
    archived: false
    body_ref: "an-preempt-006"
  - id: "an-preempt-007"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.701020Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["persistence", "aspnet"]
    source: "cross-project"
    archived: false
    body_ref: "an-preempt-007"
  - id: "an-preempt-008"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.701020Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["configuration", "aspnet"]
    source: "cross-project"
    archived: false
    body_ref: "an-preempt-008"
---
# Cross-Project Learnings: aspnet

## PREEMPT items

### AN-PREEMPT-001: Singleton services must not depend on Scoped services
<a id="an-preempt-001"></a>
- **Domain:** dependency-injection
- **Pattern:** Injecting a Scoped service (e.g., DbContext) into a Singleton causes a captive dependency — the Scoped instance is never disposed and reused across requests. Use `IServiceScopeFactory` to create a scope inside Singleton methods.
- **Confidence:** HIGH
- **Hit count:** 0

### AN-PREEMPT-002: Async deadlocks from .Result or .Wait() on tasks
<a id="an-preempt-002"></a>
- **Domain:** concurrency
- **Pattern:** Calling `.Result` or `.Wait()` on a Task in ASP.NET blocks the synchronization context and causes deadlocks. Always use `await` end-to-end. Pass `CancellationToken` from controller actions through all I/O calls.
- **Confidence:** HIGH
- **Hit count:** 0

### AN-PREEMPT-003: EF Core lazy loading silently causes N+1 queries in APIs
<a id="an-preempt-003"></a>
- **Domain:** persistence
- **Pattern:** When lazy-loading proxies are enabled, accessing a navigation property inside a loop triggers one query per iteration. Use `.Include()` for eager loading or `.AsNoTracking()` with explicit projections for read paths.
- **Confidence:** HIGH
- **Hit count:** 0

### AN-PREEMPT-004: ProblemDetails not returned for non-ApiController endpoints
<a id="an-preempt-004"></a>
- **Domain:** error-handling
- **Pattern:** The automatic ProblemDetails response format only applies to controllers decorated with `[ApiController]`. Minimal API endpoints and controllers without the attribute return plain text errors. Register `AddProblemDetails()` and a global exception handler for consistency.
- **Confidence:** MEDIUM
- **Hit count:** 0

### AN-PREEMPT-005: CancellationToken not propagated breaks graceful shutdown
<a id="an-preempt-005"></a>
- **Domain:** concurrency
- **Pattern:** Controller actions receive a `CancellationToken` but it is often not passed to downstream service and repository calls. When the client disconnects, long-running queries continue executing. Always propagate the token through the entire call chain.
- **Confidence:** HIGH
- **Hit count:** 0

### AN-PREEMPT-006: CORS AllowAnyOrigin with AllowCredentials is rejected by browsers
<a id="an-preempt-006"></a>
- **Domain:** security
- **Pattern:** Configuring `.AllowAnyOrigin().AllowCredentials()` in CORS policy throws at runtime in ASP.NET Core and is blocked by browsers. Specify explicit origins when credentials are needed.
- **Confidence:** HIGH
- **Hit count:** 0

### AN-PREEMPT-007: DbContext registered as Singleton causes concurrency exceptions
<a id="an-preempt-007"></a>
- **Domain:** persistence
- **Pattern:** `DbContext` is not thread-safe. Registering it as Singleton (or capturing it in a Singleton service) causes `InvalidOperationException` under concurrent requests. Always register DbContext as Scoped.
- **Confidence:** HIGH
- **Hit count:** 0

### AN-PREEMPT-008: IOptions vs IOptionsSnapshot vs IOptionsMonitor confusion
<a id="an-preempt-008"></a>
- **Domain:** configuration
- **Pattern:** `IOptions<T>` reads config once at startup. `IOptionsSnapshot<T>` reloads per request (Scoped). `IOptionsMonitor<T>` reloads on change (Singleton-safe). Using `IOptions` for config that changes at runtime silently returns stale values.
- **Confidence:** MEDIUM
- **Hit count:** 0
