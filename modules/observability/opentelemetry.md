# OpenTelemetry (OTLP)

## Overview

OpenTelemetry (OTel) is the vendor-neutral standard for distributed observability: traces, metrics, and logs unified under one SDK and wire protocol (OTLP). It replaces per-vendor SDKs with a single instrumentation layer that exports to any backend.

## Architecture Patterns

### Signal flow
```
Application code
  → SDK (tracer/meter/logger providers)
  → Processor/BatchExporter
  → OTLP exporter (gRPC :4317 or HTTP :4318)
  → OTel Collector
  → Backend (Jaeger, Prometheus, Loki, …)
```

Always route through an **OTel Collector** in production — it decouples apps from backends, handles retries, tail-sampling, and fan-out. Direct-to-backend is only acceptable in development.

### Resource attributes
Set these at SDK initialization; they propagate to every signal:
- `service.name` — unique logical service identifier
- `service.version` — semver from build artefact
- `service.namespace` — team or domain grouping
- `deployment.environment` — `production`, `staging`, `development`

### Auto-instrumentation vs manual spans
- **Auto-instrumentation**: use language agents (Java agent, Node.js `--require`, Python `opentelemetry-instrument`) to capture HTTP, DB, and messaging calls with zero code changes. Enable first.
- **Manual spans**: add for business-significant operations not covered by auto-instrumentation (workflow steps, cache hits, critical algorithms).

```
// Manual span example (pseudocode)
span = tracer.startSpan("order.process", {kind: SpanKind.INTERNAL})
span.setAttributes({
  "order.id": orderId,
  "order.items_count": items.length,
})
try:
  result = processOrder(...)
  span.setStatus(OK)
  return result
catch err:
  span.recordException(err)
  span.setStatus(ERROR, err.message)
  throw
finally:
  span.end()
```

## Context Propagation

Use **W3C Trace Context** (`traceparent`, `tracestate` headers) — it is the OTel default and is interoperable with all major vendors.

- Never use B3 or Zipkin headers in new code unless integrating with a legacy system that cannot be updated.
- Propagate context through message queues via carrier injection/extraction on message attributes.
- Extract incoming context at service entry points (HTTP middleware, queue consumers) before creating child spans.

Baggage (`baggage` header) carries key-value pairs across the whole trace. Use sparingly — it adds header overhead and is visible to all services. Never put PII or secrets in baggage.

## Sampling Strategies

| Strategy | When to use |
|----------|-------------|
| Head-based (probabilistic) | Default; simple, low overhead. Set 10–100% in dev, 1–10% in prod. |
| Head-based (rate-limiting) | Steady sample volume regardless of traffic spikes. |
| Tail-based (Collector) | Error/latency-triggered; samples 100% of slow/failed traces. Requires stateful Collector. |
| Always-on | Dev/test only. Never in high-traffic production. |

Configure tail sampling in the Collector `tailsampling` processor — do not implement it in the SDK.

## Exporters

| Exporter | Protocol | Default port | Use case |
|----------|----------|-------------|----------|
| OTLP gRPC | HTTP/2 | 4317 | Production; efficient, supports streaming |
| OTLP HTTP | HTTP/1.1 | 4318 | Environments where gRPC is blocked |
| Jaeger (native) | Thrift/UDP | 6831 | Legacy Jaeger deployments only |
| Zipkin | HTTP | 9411 | Legacy Zipkin deployments only |

Prefer OTLP gRPC in production. Configure TLS and bearer token authentication on the Collector endpoint.

## Span Naming Conventions

Follow OTel semantic conventions (`semconv`):
- HTTP server: `{HTTP method} {route}` → `GET /users/{id}`
- HTTP client: `{HTTP method}` → `GET`
- DB: `{db.operation} {db.name}.{table}` → `SELECT users`
- Messaging consumer: `{topic} receive`
- Internal: `{noun}.{verb}` → `order.validate`, `cache.lookup`

Never include dynamic values (IDs, parameter values) in span names — high cardinality breaks indexing.

## Performance

- Use **batch span processors** (not sync) in production; flush on shutdown.
- Set `OTEL_BSP_MAX_QUEUE_SIZE` and `OTEL_BSP_EXPORT_TIMEOUT` appropriate to traffic volume.
- Limit span attribute values to <256 bytes; truncate longer strings.
- Cap attribute count per span (`OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT`, default 128).
- Use exemplars to link metrics to representative traces without full trace overhead.

## Security

- Never record PII, passwords, tokens, or credit card numbers in span attributes or baggage.
- Restrict Collector OTLP endpoints to internal networks; require mTLS or bearer tokens for external.
- Redact sensitive query parameters before setting `url.full` or `http.url` attributes.
- Audit `baggage` values — they cross service boundaries and may be logged by intermediaries.

## Testing

- Use in-memory exporters (`InMemorySpanExporter`) to assert span creation, names, attributes, and parent-child relationships in unit tests.
- Verify context propagation with integration tests that cross HTTP or queue boundaries.
- Assert span status: `ERROR` status must be set on exceptions; `OK` on successful completion.
- Check that resource attributes are present on all exported spans in smoke tests.

## Dos

- Initialize the SDK once at application startup; share a single TracerProvider/MeterProvider.
- Always call `span.end()` in a `finally` block (or use context manager / `using` pattern).
- Set `service.name` and `service.version` resource attributes on every service.
- Use semantic convention attribute names (`http.request.method`, `db.system`, etc.) for automatic backend enrichment.
- Add `span.recordException()` before setting ERROR status so the stack trace is attached to the span.
- Run an OTel Collector sidecar or DaemonSet in Kubernetes; never export directly to the backend in production.

## Don'ts

- Don't put high-cardinality values (user IDs, request bodies, UUIDs) in span **names** — use span **attributes** instead.
- Don't use `AlwaysOn` sampling in production traffic (>1k req/s).
- Don't block application startup waiting for the exporter to connect; use async batch processors.
- Don't mix OTel SDK with vendor SDKs (Datadog agent + OTel SDK simultaneously) without explicit bridging.
- Don't put PII or secrets in span attributes, baggage, or log bodies exported via OTLP.
- Don't create spans around trivially fast operations (<1ms) unless debugging specific hot paths.
