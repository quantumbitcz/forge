# Micrometer

## Overview

Micrometer is the JVM metrics facade — the "SLF4J of metrics". It provides a vendor-neutral API over a pluggable `MeterRegistry` and ships adapters for Prometheus, Atlas, Datadog, CloudWatch, and others. Use it for dimensional (tag-based) application metrics independent of the backend.

## Architecture Patterns

### Meter registry
```
Application code → Micrometer API → MeterRegistry → Backend adapter → Time-series DB
```

Use a `CompositeMeterRegistry` when you need to push to multiple backends simultaneously (e.g., Prometheus for alerting + Datadog for dashboards).

### Meter types

| Type | Use case | Example |
|------|----------|---------|
| `Counter` | Monotonically increasing count | requests served, errors |
| `Gauge` | Point-in-time snapshot | queue depth, active connections, heap used |
| `Timer` | Duration + throughput | HTTP request latency, DB query time |
| `DistributionSummary` | Value distribution (non-time) | payload size, batch size |
| `LongTaskTimer` | Long-running in-flight tasks | scheduled jobs, background imports |

### Naming convention
Follow `{noun}.{verb}` or `{noun}.{noun}` patterns in dot-notation; Micrometer translates to the backend convention automatically (Prometheus uses `_` separators):
```
http.server.requests      → http_server_requests_seconds (Prometheus)
db.connection.pool.size   → db_connection_pool_size (Prometheus)
order.processing.time     → order_processing_time_seconds
cache.hit.ratio           → cache_hit_ratio
```

Always include a unit suffix when the unit is not obvious (`seconds`, `bytes`, `total`). Never include units that Micrometer appends automatically (`Timer` always appends `_seconds`).

## Configuration

### SLO histograms and percentile approximation

```java
Timer.builder("http.server.requests")
    .publishPercentileHistogram()          // exact histogram for Prometheus PromQL
    .publishPercentiles(0.5, 0.95, 0.99)  // client-side percentiles (less accurate)
    .sla(Duration.ofMillis(100), Duration.ofMillis(500))  // SLO buckets
    .register(registry);
```

Prefer `publishPercentileHistogram()` over `publishPercentiles()` when the backend supports histogram queries (Prometheus `histogram_quantile`). Client-side percentiles are pre-aggregated and cannot be re-aggregated across instances.

### Custom tags (dimensions)
Tags are the core of dimensional metrics — they let you slice by service, endpoint, status, region:
```java
registry.counter("payment.attempts",
    "method", "card",
    "region", "eu-west",
    "outcome", "success"
).increment();
```

**Tag cardinality budget:** Every unique tag-value combination creates a new time series. Keep per-metric tag-value combinations below 1,000. Never use user IDs, order IDs, or free-form strings as tag values.

### Annotations (`@Timed`, `@Counted`)
```java
@Timed(value = "orders.create", percentiles = {0.5, 0.95, 0.99}, histogram = true)
@Counted(value = "orders.create.calls", extraTags = {"layer", "service"})
public Order createOrder(CreateOrderRequest request) { … }
```

Requires `TimedAspect` and `CountedAspect` beans registered in the application context.

### Custom `MeterBinder`
Implement `MeterBinder` for external resources (thread pools, connection pools, caches) that need lifecycle-aware metric registration:
```java
public class OrderQueueMetrics implements MeterBinder {
    private final OrderQueue queue;
    @Override
    public void bindTo(MeterRegistry registry) {
        Gauge.builder("order.queue.depth", queue, OrderQueue::size)
            .description("Current number of pending orders")
            .register(registry);
    }
}
```

## Performance

- Meter lookup (`registry.counter(...)`) is cheap but not free — cache the meter reference in a field rather than looking it up on every call.
- `Timer.record(Supplier)` and `Timer.recordCallable(Callable)` are preferred over manual start/stop to guarantee `stop()` is always called.
- `DistributionSummary` and histogram `Timer` add memory overhead proportional to bucket count — review bucket configuration for high-traffic metrics.
- Use `AsyncGauge` for gauges backed by blocking or slow calls (DB counts, external API).

## Security

- Never use PII (user email, phone, name) as tag values — tags end up in time-series labels visible to anyone with metrics access.
- Restrict the Prometheus scrape endpoint (`/actuator/prometheus`) to monitoring infrastructure (network policy or authentication).
- Sanitize exception class names before using them as tags (`exception` tag) — avoid leaking internal package structure.

## Testing

- Use `SimpleMeterRegistry` or `TestMeterRegistry` in unit tests; no external backend needed.
- Assert counter increments, timer counts, and gauge values via `registry.get("metric.name").counter().count()`.
- Test `MeterBinder` implementations by registering them against a `SimpleMeterRegistry` and asserting the expected meters are present.

## Dos

- Register meters at startup, not on first use — pre-registration ensures zero-value series appear in dashboards immediately.
- Use `description()` on every meter; it appears in Prometheus `/metrics` `# HELP` lines.
- Use `baseUnit()` on `DistributionSummary` and `Gauge` to clarify units (`"bytes"`, `"requests"`).
- Use composite registry to fanout to multiple backends without code changes.
- Add `application` and `environment` common tags at registry level so every metric carries them.

## Don'ts

- Don't use high-cardinality values (IDs, UUIDs, email addresses) as tag values.
- Don't create unbounded gauges that never deregister — use `Gauge.builder(...).strongReference(true)` or `WeakReference` patterns to avoid memory leaks.
- Don't call `registry.find(...)` on the hot path — cache meter references.
- Don't publish both `publishPercentiles` and `publishPercentileHistogram` for the same timer unless deliberately accepting the overhead of both.
- Don't mix naming conventions within a service — pick `noun.verb` and stick to it.
