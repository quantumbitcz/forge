---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
# Cross-Project Learnings: fastapi

## PREEMPT items

### FA-PREEMPT-001: Synchronous I/O in async handlers blocks the entire event loop
- **Domain:** concurrency
- **Pattern:** Calling synchronous database drivers, `time.sleep()`, or CPU-heavy functions inside `async def` handlers blocks all concurrent requests. Use `def` (thread pool) for sync I/O or switch to async drivers (asyncpg, aiohttp). Never mix sync I/O in async handlers.
- **Confidence:** HIGH
- **Hit count:** 0

### FA-PREEMPT-002: Dependency injection with yield not cleaned up on exceptions
- **Domain:** dependency-injection
- **Pattern:** Dependencies using `yield` (e.g., DB session) must wrap the yield in try/finally to ensure cleanup runs even when the handler raises. Without finally, database sessions leak on unhandled exceptions.
- **Confidence:** HIGH
- **Hit count:** 0

### FA-PREEMPT-003: Returning ORM models instead of Pydantic schemas leaks internal fields
- **Domain:** serialization
- **Pattern:** Returning SQLAlchemy/Tortoise models directly from endpoints exposes internal fields (password hashes, internal IDs, timestamps). Always map to Pydantic response schemas with `model_config = ConfigDict(from_attributes=True)`.
- **Confidence:** HIGH
- **Hit count:** 0

### FA-PREEMPT-004: Missing response_model causes undocumented API responses
- **Domain:** api-design
- **Pattern:** Endpoints without `response_model` in the decorator produce no OpenAPI response schema. Clients see `200 OK` with an untyped body. Always specify `response_model=XxxResponse` even for simple endpoints to generate accurate API documentation.
- **Confidence:** MEDIUM
- **Hit count:** 0

### FA-PREEMPT-005: Global mutable state shared across async workers causes race conditions
- **Domain:** concurrency
- **Pattern:** Module-level mutable variables (dicts, lists, counters) are shared across all async tasks in a single worker. Concurrent requests can corrupt the state. Use dependency injection for request-scoped state or `asyncio.Lock` for truly shared state.
- **Confidence:** HIGH
- **Hit count:** 0

### FA-PREEMPT-006: BackgroundTasks exception silently swallowed
- **Domain:** error-handling
- **Pattern:** Exceptions raised in `BackgroundTasks` are logged but not propagated to the client (the response is already sent). Critical background operations (payment processing, email sending) need their own error handling and retry logic, not just `BackgroundTasks`.
- **Confidence:** MEDIUM
- **Hit count:** 0

### FA-PREEMPT-007: Pydantic V2 migration breaks model_validator and validator signatures
- **Domain:** build
- **Pattern:** Pydantic V1 used `@validator` and `@root_validator` with different signatures than V2's `@field_validator` and `@model_validator`. Mixing V1 and V2 patterns in the same codebase causes silent validation failures. Use `from pydantic import field_validator` consistently.
- **Confidence:** HIGH
- **Hit count:** 0
