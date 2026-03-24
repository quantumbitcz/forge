# Health Checks

## Overview

Health checks expose the operational state of a service to infrastructure (Kubernetes, load balancers, service meshes). Three probe semantics matter: **liveness** (is the process alive?), **readiness** (can it serve traffic?), and **startup** (has it finished initialising?). Wrong probe design causes unnecessary restarts or routes traffic to broken instances.

## Kubernetes Probe Semantics

| Probe | Failure action | What to check |
|-------|---------------|---------------|
| `livenessProbe` | Kill and restart the pod | Is the process deadlocked or in an unrecoverable state? |
| `readinessProbe` | Remove pod from Service endpoints | Can this instance serve requests right now? |
| `startupProbe` | Kill the pod if it hasn't started by the deadline | Has the app finished its slow initialisation (migrations, cache warm-up)? |

**Critical distinction:** A liveness failure causes a restart (potentially losing in-flight requests). Only fail liveness for truly unrecoverable states — deadlock, OOM, corrupted internal state. A readiness failure gracefully removes the pod from load balancing without restarting it.

```yaml
# Kubernetes probe configuration example
livenessProbe:
  httpGet:
    path: /health/live
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 30
  failureThreshold: 3
  timeoutSeconds: 5

readinessProbe:
  httpGet:
    path: /health/ready
    port: 8080
  periodSeconds: 10
  failureThreshold: 3
  timeoutSeconds: 5

startupProbe:
  httpGet:
    path: /health/startup
    port: 8080
  periodSeconds: 5
  failureThreshold: 30    # 30 * 5s = 150s startup budget
  timeoutSeconds: 5
```

## Dependency Health Checks

### What each probe should check

**Liveness** — only internal process health:
- Thread pool alive (not fully exhausted / deadlocked)
- Critical internal queues not overflowing
- No unrecoverable error state set by the application itself
- Do NOT check external dependencies — a DB outage should not restart the pod

**Readiness** — external dependencies required to serve requests:
- Primary database reachable and responding within SLA (e.g., <500ms ping)
- Cache (Redis) reachable if cache-miss is unacceptable
- Required downstream services reachable
- Startup tasks (migrations, config load) complete

**Startup** — initialisation sequence complete:
- Database migrations applied
- Caches pre-warmed if required
- Configuration loaded from remote config service
- Connections established and pooled

### Dependency check patterns

```
// Pseudocode — readiness check
func checkReadiness() -> HealthResult:
    checks = [
        checkDatabase(timeout=500ms),
        checkCache(timeout=200ms),
        checkMessageBroker(timeout=300ms),
    ]
    results = runAll(checks)
    if any(r.status == UNHEALTHY for r in results):
        return HealthResult(status=UNHEALTHY, details=results)
    if any(r.status == DEGRADED for r in results):
        return HealthResult(status=DEGRADED, details=results)
    return HealthResult(status=HEALTHY, details=results)
```

## Degraded States (Partial Health)

Services are rarely fully healthy or fully broken. Use three-state health: `UP`, `DEGRADED`, `DOWN`.

| Status | HTTP | Meaning |
|--------|------|---------|
| `UP` (healthy) | 200 | All dependencies healthy; full functionality |
| `DEGRADED` | 200 | One or more non-critical dependencies degraded; reduced functionality but still serving |
| `DOWN` (unhealthy) | 503 | Critical dependency unavailable; cannot serve requests |

Kubernetes probes read HTTP status codes: return `200` for both `UP` and `DEGRADED` (still ready to serve), `503` for `DOWN`.

Include a structured body with per-dependency status for observability tooling:
```json
{
  "status": "DEGRADED",
  "checks": {
    "database": { "status": "UP", "latency_ms": 12 },
    "cache": { "status": "DEGRADED", "latency_ms": 890, "message": "High latency" },
    "payment_api": { "status": "UP", "latency_ms": 45 }
  }
}
```

## Health Aggregation Patterns

For services with many dependencies, aggregate checks with explicit criticality:
```
CRITICAL dependencies: DB, auth service — DOWN if any are DOWN
NON-CRITICAL dependencies: cache, analytics sink — DEGRADED if any are DOWN
```

Implement a circuit breaker around external dependency checks: if a dependency fails consistently, stop checking it on every probe call (cache the last result for 5–30 seconds) to prevent probe timeouts from cascading.

## Circuit Breaker Integration

When a circuit breaker is OPEN (dependency considered unavailable), the health check for that dependency should immediately report `DOWN` or `DEGRADED` without making a network call — the circuit is open precisely because the network call was failing.

```
dependency_status =
  if circuitBreaker.isOpen(dep):  DEGRADED (or DOWN if critical)
  else:                           checkLive(dep, timeout=200ms)
```

This prevents health check probes from consuming connection pool resources during outages.

## Health Endpoint Security

- Expose liveness and readiness endpoints on a **separate internal port** (e.g., 8081) distinct from the public API port (8080). Apply network policies to restrict access to the health port to infrastructure only.
- Do NOT expose detailed dependency status (including internal hostnames, latency, error messages) on the public-facing API. Expose detailed health only on the internal management port.
- Simple liveness (`/health/live`) can be unauthenticated — it contains no sensitive information.
- Readiness and detailed health (`/health/ready`, `/health/detail`) should require cluster-internal access control.

## Performance

- Health checks must be **fast**: liveness < 100ms, readiness < 500ms. Set probe `timeoutSeconds` accordingly.
- Use connection pool `ping` rather than a full query for DB health checks.
- Cache external dependency results for 5–30 seconds to avoid hammering dependencies on every probe interval.
- Never perform migrations, cache warming, or heavy computation inside a health check handler.

## Testing

- Unit test each dependency health checker independently with mocked clients.
- Integration test the health endpoints with a real application context to verify all checks are wired up.
- Test the `DEGRADED` path: simulate a non-critical dependency failure and assert the endpoint returns `200 DEGRADED` and Kubernetes does not remove the pod from load balancing.
- Test the `DOWN` path: simulate a critical dependency failure and assert the endpoint returns `503` and Kubernetes removes the pod from Service endpoints.
- Verify that health checks complete within the configured `timeoutSeconds`.

## Dos

- Use three distinct endpoints: `/health/live`, `/health/ready`, `/health/startup`.
- Keep liveness checks internal-only (no external dependency calls).
- Return structured JSON with per-dependency status for debugging.
- Cache external dependency check results to prevent probe-induced load.
- Expose detailed health on internal ports only.

## Don'ts

- Don't check external dependencies in livenessProbe — an external outage will trigger unnecessary pod restarts.
- Don't return `503` for `DEGRADED` state — this removes the pod from load balancing unnecessarily.
- Don't expose internal hostnames, error details, or stack traces on the public health endpoint.
- Don't make health checks synchronous with slow dependencies without a tight timeout.
- Don't skip the startupProbe for applications with slow initialisation — use it instead of inflating `initialDelaySeconds` on liveness.
- Don't treat health endpoints as admin consoles — they should answer one question: "can this instance serve traffic?"
