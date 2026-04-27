---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "vp-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.828104Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "vapor"]
    source: "cross-project"
    archived: false
    body_ref: "#vp-preempt-001"
  - id: "vp-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.828104Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "vapor"]
    source: "cross-project"
    archived: false
    body_ref: "#vp-preempt-002"
  - id: "vp-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.828104Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "vapor"]
    source: "cross-project"
    archived: false
    body_ref: "#vp-preempt-003"
  - id: "vp-preempt-004"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.828104Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["persistence", "vapor"]
    source: "cross-project"
    archived: false
    body_ref: "#vp-preempt-004"
  - id: "vp-preempt-005"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.828104Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["migrations", "vapor"]
    source: "cross-project"
    archived: false
    body_ref: "#vp-preempt-005"
  - id: "vp-preempt-006"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.828104Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["architecture", "vapor"]
    source: "cross-project"
    archived: false
    body_ref: "#vp-preempt-006"
  - id: "vp-preempt-007"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.828104Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["configuration", "vapor"]
    source: "cross-project"
    archived: false
    body_ref: "#vp-preempt-007"
---
# Cross-Project Learnings: vapor

## PREEMPT items

### VP-PREEMPT-001: EventLoopFuture chains in new code bypass structured concurrency
<a id="vp-preempt-001"></a>
- **Domain:** concurrency
- **Pattern:** Vapor 4.50+ supports `async/await` natively. Using `EventLoopFuture` chains in new code creates callback-heavy code that is harder to read, debug, and test. Always use `async throws` handlers, repository methods, and middleware.
- **Confidence:** HIGH
- **Hit count:** 0

### VP-PREEMPT-002: Returning Fluent models directly from routes leaks internal fields
<a id="vp-preempt-002"></a>
- **Domain:** security
- **Pattern:** Returning `User` (Fluent model) directly from a route handler exposes all stored fields including password hashes, internal timestamps, and soft-delete flags. Always map to a response DTO (`UserResponse`) that explicitly includes only safe fields.
- **Confidence:** HIGH
- **Hit count:** 0

### VP-PREEMPT-003: Blocking calls on the event loop freeze all concurrent requests
<a id="vp-preempt-003"></a>
- **Domain:** concurrency
- **Pattern:** Calling `Thread.sleep`, synchronous file I/O, or CPU-heavy computation directly in a route handler blocks the NIO event loop thread, freezing all concurrent requests on that loop. Use `req.application.threadPool.runIfActive` for blocking work.
- **Confidence:** HIGH
- **Hit count:** 0

### VP-PREEMPT-004: N+1 queries from Fluent eager-loading not applied
<a id="vp-preempt-004"></a>
- **Domain:** persistence
- **Pattern:** Accessing `$user.posts` (parent-child relationship) in a loop without prior eager-loading triggers one query per iteration. Use `.with(\.$posts)` in Fluent queries to eager-load relationships, or `.join` for multi-table queries.
- **Confidence:** HIGH
- **Hit count:** 0

### VP-PREEMPT-005: Missing reverse migration blocks rollback
<a id="vp-preempt-005"></a>
- **Domain:** migrations
- **Pattern:** Fluent migrations that implement `prepare()` without `revert()` throw a fatal error on rollback. Always implement `revert()` with the inverse operation (drop table, remove column). Never modify an already-deployed migration.
- **Confidence:** HIGH
- **Hit count:** 0

### VP-PREEMPT-006: req.application used inside route handler instead of req properties
<a id="vp-preempt-006"></a>
- **Domain:** architecture
- **Pattern:** Accessing `req.application.databases` or other `app` properties inside route handlers bypasses per-request scoping. Use `req.db` for database access, `req.logger` for logging, and `req.auth` for authentication context.
- **Confidence:** MEDIUM
- **Hit count:** 0

### VP-PREEMPT-007: Environment.get() returns nil without clear error for missing env vars
<a id="vp-preempt-007"></a>
- **Domain:** configuration
- **Pattern:** `Environment.get("SECRET_KEY")` returns `nil` if the variable is not set, and the app may start with a nil value causing silent failures downstream. Validate all required environment variables at startup with a guard and descriptive `fatalError`.
- **Confidence:** MEDIUM
- **Hit count:** 0
