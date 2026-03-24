# Structured Logging

## Overview

Structured logging emits machine-readable log records (JSON) rather than freeform text strings. Each field is a key-value pair that log aggregators (Loki, Elasticsearch, Splunk, CloudWatch) can index and query without regex parsing.

## Log Format

Every log record must include these fields:

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | ISO-8601 UTC | `"2026-03-24T12:34:56.789Z"` |
| `level` | string | `ERROR`, `WARN`, `INFO`, `DEBUG` |
| `message` | string | Human-readable summary; static, no dynamic data |
| `service` | string | Service name (same as `service.name` OTel resource) |
| `version` | string | Service version |
| `correlation_id` | string | Request-scoped ID (set at API gateway or service entry) |
| `trace_id` | string | OTel trace ID (from active span); enables log-trace linking |
| `span_id` | string | OTel span ID |
| `environment` | string | `production`, `staging`, `development` |

Additional domain fields are allowed; keep them consistent and documented.

Example record:
```json
{
  "timestamp": "2026-03-24T12:34:56.789Z",
  "level": "ERROR",
  "message": "Order payment failed",
  "service": "order-service",
  "version": "1.4.2",
  "correlation_id": "req-7f3a9c2b",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "environment": "production",
  "order_id": "ord-8812",
  "payment_provider": "stripe",
  "error_code": "card_declined"
}
```

## Log Levels

| Level | When to use | Action expected |
|-------|-------------|-----------------|
| `ERROR` | Operation failed; requires human intervention | Alert / page on-call |
| `WARN` | Degraded behaviour; system recovered or retried | Monitor; may require action |
| `INFO` | Significant business events (order created, user registered) | No action; audit trail |
| `DEBUG` | Developer troubleshooting data; internal state | Disabled in production by default |
| `TRACE` | Very fine-grained execution details | Disabled in production always |

Rules:
- `ERROR` must be actionable — if nobody needs to act, use `WARN`.
- `INFO` should tell the business story; one `INFO` per meaningful business event, not per function call.
- Never log at `DEBUG` in a production hot path — use sampling or conditional logging.
- `WARN` for retried-and-succeeded operations: the system recovered but the anomaly is worth tracking.

## Context Enrichment (MDC/NDC)

Attach request-scoped fields to the logging context at the service entry point so all downstream log calls within the same request automatically include them:

```
// Pseudocode — set once in middleware / filter
MDC.put("correlation_id", request.header("X-Correlation-Id") ?? UUID.random())
MDC.put("trace_id", currentSpan.traceId)
MDC.put("span_id", currentSpan.spanId)
MDC.put("user_id", authenticatedUser.id)  // if non-PII (internal ID, not email)
// ... handle request ...
MDC.clear()  // always clear in finally block
```

Never pass correlation IDs as function parameters — propagate via MDC/context so callees log them automatically.

Generate a `correlation_id` at the outermost entry point (API gateway preferred; service edge as fallback). Echo it in response headers (`X-Correlation-Id`) so callers can reference it in support requests.

## Sensitive Data Masking

Before logging any field, classify it:

| Category | Examples | Treatment |
|----------|----------|-----------|
| PII — direct | Name, email, phone, SSN, DOB | Never log; use opaque internal ID |
| PII — indirect | IP address, device fingerprint | Log only if legally required; truncate/hash |
| Credentials | Passwords, API keys, tokens | Never log under any circumstance |
| Financial | Card number, full IBAN | Never log; log last 4 digits only |
| Health | Medical records, diagnoses | Never log |
| Internal IDs | `user_id`, `order_id` | Safe to log |

Implement a `mask(value)` utility used in serialization layers — do not rely on developers remembering to mask at every call site.

Redact HTTP request/response bodies when logging at `DEBUG` — body logging must be opt-in and must mask sensitive fields before output.

## Request-Scoped Correlation IDs

```
Client → API Gateway → Service A → Service B → DB
                 ↓           ↓           ↓
           X-Correlation-Id propagated in all HTTP headers
           and message queue metadata
```

- Propagate `correlation_id` via HTTP header (`X-Correlation-Id`), message attributes, and gRPC metadata.
- Validate that incoming `correlation_id` matches expected format (UUID v4); reject or regenerate if malformed.
- Store `correlation_id` in MDC for the duration of the request; include in all log records.

## Performance

- Use async log appenders (async queue between log call and I/O) to prevent logging from blocking application threads.
- Set reasonable queue capacity; on overflow prefer dropping DEBUG/TRACE records over blocking the application.
- Avoid constructing expensive string representations in log arguments when the level is disabled — use lazy evaluation (`log.debug { "State: ${expensiveCompute()}" }`).
- Log aggregators ingest JSON natively — never pretty-print JSON in production (wastes bytes and adds parsing overhead).

## Security

- Mask sensitive fields at the serializer level, not at individual log call sites.
- Restrict log storage access — logs contain operational detail useful for attackers.
- Enable log integrity: forward logs to an append-only sink (S3, WORM storage) immediately so they cannot be tampered with post-incident.
- Rotate log files and apply retention policies compliant with data protection regulations (GDPR, HIPAA).
- Never log outbound HTTP request bodies that may contain bearer tokens or API keys.

## Testing

- Assert that sensitive fields (passwords, tokens, emails) are absent from log output in unit tests.
- Verify `correlation_id` and `trace_id` are present in all log records emitted during a request in integration tests.
- Test MDC cleanup: assert MDC is clear after request completion (no context bleed between requests).
- Validate log level filtering: `DEBUG` records must not appear at `INFO` log level.

## Dos

- Emit one `INFO` log per meaningful business event with all relevant domain context as structured fields.
- Always include `trace_id` and `span_id` for log-trace correlation.
- Generate and propagate `correlation_id` at the service entry point.
- Use static message strings — put variable data in separate fields (`"message": "Order created", "order_id": "ord-8812"`).
- Clear MDC in a `finally` block to prevent context bleed between requests.

## Don'ts

- Don't log PII, credentials, or payment data under any log level.
- Don't use freeform string concatenation in log messages — use structured fields.
- Don't log at `ERROR` for expected business exceptions (validation failures, not-found) — use `WARN` or `INFO`.
- Don't emit DEBUG logs on the hot path in production — use sampling or remove them.
- Don't log request/response bodies without explicit masking of sensitive fields.
- Don't rely on log output format staying as plain text — write your log parsing against the JSON schema.
