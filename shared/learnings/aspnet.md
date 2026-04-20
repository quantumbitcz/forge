---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
# Cross-Project Learnings: aspnet

## PREEMPT items

### AN-PREEMPT-001: Singleton services must not depend on Scoped services
- **Domain:** dependency-injection
- **Pattern:** Injecting a Scoped service (e.g., DbContext) into a Singleton causes a captive dependency — the Scoped instance is never disposed and reused across requests. Use `IServiceScopeFactory` to create a scope inside Singleton methods.
- **Confidence:** HIGH
- **Hit count:** 0

### AN-PREEMPT-002: Async deadlocks from .Result or .Wait() on tasks
- **Domain:** concurrency
- **Pattern:** Calling `.Result` or `.Wait()` on a Task in ASP.NET blocks the synchronization context and causes deadlocks. Always use `await` end-to-end. Pass `CancellationToken` from controller actions through all I/O calls.
- **Confidence:** HIGH
- **Hit count:** 0

### AN-PREEMPT-003: EF Core lazy loading silently causes N+1 queries in APIs
- **Domain:** persistence
- **Pattern:** When lazy-loading proxies are enabled, accessing a navigation property inside a loop triggers one query per iteration. Use `.Include()` for eager loading or `.AsNoTracking()` with explicit projections for read paths.
- **Confidence:** HIGH
- **Hit count:** 0

### AN-PREEMPT-004: ProblemDetails not returned for non-ApiController endpoints
- **Domain:** error-handling
- **Pattern:** The automatic ProblemDetails response format only applies to controllers decorated with `[ApiController]`. Minimal API endpoints and controllers without the attribute return plain text errors. Register `AddProblemDetails()` and a global exception handler for consistency.
- **Confidence:** MEDIUM
- **Hit count:** 0

### AN-PREEMPT-005: CancellationToken not propagated breaks graceful shutdown
- **Domain:** concurrency
- **Pattern:** Controller actions receive a `CancellationToken` but it is often not passed to downstream service and repository calls. When the client disconnects, long-running queries continue executing. Always propagate the token through the entire call chain.
- **Confidence:** HIGH
- **Hit count:** 0

### AN-PREEMPT-006: CORS AllowAnyOrigin with AllowCredentials is rejected by browsers
- **Domain:** security
- **Pattern:** Configuring `.AllowAnyOrigin().AllowCredentials()` in CORS policy throws at runtime in ASP.NET Core and is blocked by browsers. Specify explicit origins when credentials are needed.
- **Confidence:** HIGH
- **Hit count:** 0

### AN-PREEMPT-007: DbContext registered as Singleton causes concurrency exceptions
- **Domain:** persistence
- **Pattern:** `DbContext` is not thread-safe. Registering it as Singleton (or capturing it in a Singleton service) causes `InvalidOperationException` under concurrent requests. Always register DbContext as Scoped.
- **Confidence:** HIGH
- **Hit count:** 0

### AN-PREEMPT-008: IOptions vs IOptionsSnapshot vs IOptionsMonitor confusion
- **Domain:** configuration
- **Pattern:** `IOptions<T>` reads config once at startup. `IOptionsSnapshot<T>` reloads per request (Scoped). `IOptionsMonitor<T>` reloads on change (Singleton-safe). Using `IOptions` for config that changes at runtime silently returns stale values.
- **Confidence:** MEDIUM
- **Hit count:** 0
