---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "fa-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.739645Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "fastapi"]
    source: "cross-project"
    archived: false
    body_ref: "#fa-preempt-001"
  - id: "fa-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.739645Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["dependency-injection", "fastapi"]
    source: "cross-project"
    archived: false
    body_ref: "#fa-preempt-002"
  - id: "fa-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.739645Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["serialization", "fastapi"]
    source: "cross-project"
    archived: false
    body_ref: "#fa-preempt-003"
  - id: "fa-preempt-004"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.739645Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["api-design", "fastapi"]
    source: "cross-project"
    archived: false
    body_ref: "#fa-preempt-004"
  - id: "fa-preempt-005"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.739645Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "fastapi"]
    source: "cross-project"
    archived: false
    body_ref: "#fa-preempt-005"
  - id: "fa-preempt-006"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.739645Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["error-handling", "fastapi"]
    source: "cross-project"
    archived: false
    body_ref: "#fa-preempt-006"
  - id: "fa-preempt-007"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.739645Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["build", "fastapi"]
    source: "cross-project"
    archived: false
    body_ref: "#fa-preempt-007"
---
# Cross-Project Learnings: fastapi

## PREEMPT items

### FA-PREEMPT-001: Synchronous I/O in async handlers blocks the entire event loop
<a id="fa-preempt-001"></a>
- **Domain:** concurrency
- **Pattern:** Calling synchronous database drivers, `time.sleep()`, or CPU-heavy functions inside `async def` handlers blocks all concurrent requests. Use `def` (thread pool) for sync I/O or switch to async drivers (asyncpg, aiohttp). Never mix sync I/O in async handlers.
- **Confidence:** HIGH
- **Hit count:** 0

### FA-PREEMPT-002: Dependency injection with yield not cleaned up on exceptions
<a id="fa-preempt-002"></a>
- **Domain:** dependency-injection
- **Pattern:** Dependencies using `yield` (e.g., DB session) must wrap the yield in try/finally to ensure cleanup runs even when the handler raises. Without finally, database sessions leak on unhandled exceptions.
- **Confidence:** HIGH
- **Hit count:** 0

### FA-PREEMPT-003: Returning ORM models instead of Pydantic schemas leaks internal fields
<a id="fa-preempt-003"></a>
- **Domain:** serialization
- **Pattern:** Returning SQLAlchemy/Tortoise models directly from endpoints exposes internal fields (password hashes, internal IDs, timestamps). Always map to Pydantic response schemas with `model_config = ConfigDict(from_attributes=True)`.
- **Confidence:** HIGH
- **Hit count:** 0

### FA-PREEMPT-004: Missing response_model causes undocumented API responses
<a id="fa-preempt-004"></a>
- **Domain:** api-design
- **Pattern:** Endpoints without `response_model` in the decorator produce no OpenAPI response schema. Clients see `200 OK` with an untyped body. Always specify `response_model=XxxResponse` even for simple endpoints to generate accurate API documentation.
- **Confidence:** MEDIUM
- **Hit count:** 0

### FA-PREEMPT-005: Global mutable state shared across async workers causes race conditions
<a id="fa-preempt-005"></a>
- **Domain:** concurrency
- **Pattern:** Module-level mutable variables (dicts, lists, counters) are shared across all async tasks in a single worker. Concurrent requests can corrupt the state. Use dependency injection for request-scoped state or `asyncio.Lock` for truly shared state.
- **Confidence:** HIGH
- **Hit count:** 0

### FA-PREEMPT-006: BackgroundTasks exception silently swallowed
<a id="fa-preempt-006"></a>
- **Domain:** error-handling
- **Pattern:** Exceptions raised in `BackgroundTasks` are logged but not propagated to the client (the response is already sent). Critical background operations (payment processing, email sending) need their own error handling and retry logic, not just `BackgroundTasks`.
- **Confidence:** MEDIUM
- **Hit count:** 0

### FA-PREEMPT-007: Pydantic V2 migration breaks model_validator and validator signatures
<a id="fa-preempt-007"></a>
- **Domain:** build
- **Pattern:** Pydantic V1 used `@validator` and `@root_validator` with different signatures than V2's `@field_validator` and `@model_validator`. Mixing V1 and V2 patterns in the same codebase causes silent validation failures. Use `from pydantic import field_validator` consistently.
- **Confidence:** HIGH
- **Hit count:** 0
