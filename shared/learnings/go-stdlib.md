---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
# Cross-Project Learnings: go-stdlib

## PREEMPT items

### GS-PREEMPT-001: Goroutine leak from missing context cancellation
- **Domain:** concurrency
- **Pattern:** Launching goroutines without passing a cancellable `context.Context` causes them to outlive the request. Over time, leaked goroutines accumulate and exhaust memory. Always pass `ctx` and select on `ctx.Done()` in long-running goroutines. Detect leaks with `goleak` in tests.
- **Confidence:** HIGH
- **Hit count:** 0

### GS-PREEMPT-002: Concurrent map read/write causes fatal runtime panic
- **Domain:** concurrency
- **Pattern:** Go maps are not thread-safe. Concurrent reads and writes from multiple goroutines cause a non-recoverable `fatal error: concurrent map read and map write`. Use `sync.RWMutex` to protect maps or `sync.Map` for simple key-value patterns. Run tests with `-race`.
- **Confidence:** HIGH
- **Hit count:** 0

### GS-PREEMPT-003: Error wrapping with %w breaks errors.Is() chain if wrapping twice
- **Domain:** error-handling
- **Pattern:** Wrapping errors with `fmt.Errorf("outer: %w", fmt.Errorf("inner: %w", sentinel))` works, but custom error types that embed an error field AND use `%w` can create confusing chains. Keep one wrapping mechanism per error type — either `%w` or custom `Unwrap()`.
- **Confidence:** MEDIUM
- **Hit count:** 0

### GS-PREEMPT-004: http.ServeMux pattern matching changed in Go 1.22
- **Domain:** routing
- **Pattern:** Go 1.22 introduced method-aware routing (`GET /users/{id}`) in `http.ServeMux`. Code targeting Go 1.21 and below must use a third-party router or manual method checking. Ensure `go.mod` minimum version matches the routing pattern used.
- **Confidence:** HIGH
- **Hit count:** 0

### GS-PREEMPT-005: defer runs at function return, not block scope
- **Domain:** resource-management
- **Pattern:** `defer` inside a loop defers cleanup to function return, not loop iteration end. Opening resources (files, connections) in a loop with defer causes resource exhaustion. Extract loop bodies to helper functions or use explicit close at loop end.
- **Confidence:** HIGH
- **Hit count:** 0

### GS-PREEMPT-006: init() functions create hidden initialization coupling
- **Domain:** architecture
- **Pattern:** `init()` functions run before `main()` in import order, creating hidden startup dependencies that are hard to test and debug. Prefer explicit initialization in `main()` with dependency injection. Reserve `init()` for registering drivers or codecs only.
- **Confidence:** MEDIUM
- **Hit count:** 0

### GS-PREEMPT-007: JSON struct tags missing cause silent field name mismatches
- **Domain:** serialization
- **Pattern:** Go's `encoding/json` uses field names verbatim (PascalCase) when `json:` tags are missing. APIs expecting `camelCase` receive wrong field names and clients silently ignore them. Always add `json:"fieldName"` tags on all serialized struct fields.
- **Confidence:** HIGH
- **Hit count:** 0
