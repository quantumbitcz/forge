# Jaeger

## Overview

Jaeger is an open-source distributed tracing platform (CNCF graduated). It collects, stores, and visualises trace data from OpenTelemetry-instrumented services. In new deployments, use Jaeger as a trace backend receiving OTLP — the native Jaeger protocol (Thrift/UDP) is legacy.

## Architecture Patterns

### Development topology (all-in-one)
```
Services (OTLP gRPC → localhost:4317)
  → jaeger-all-in-one (in-memory storage)
  → Jaeger UI (localhost:16686)
```

`jaeger-all-in-one` stores data in-memory. Data is lost on restart. Use only for local development and CI integration tests.

### Production topology
```
Services (OTLP gRPC)
  → OTel Collector (tail-sampling, fan-out)
  → Jaeger Collector (port 4317 OTLP or 14250 gRPC)
  → Storage backend (Elasticsearch or Cassandra)
  → Jaeger Query (UI + API, port 16686)
```

Never route production traffic directly from services to Jaeger Collector — always via OTel Collector for buffering, retry, and tail sampling.

### Storage backends

| Backend | Use case | Notes |
|---------|----------|-------|
| In-memory | Development only | Data lost on restart |
| Elasticsearch / OpenSearch | Production (recommended) | Full-text search on tags, scales horizontally |
| Cassandra | High-write production | Append-optimised; no full-text tag search |
| Kafka (buffer) | High-throughput ingestion | Jaeger Ingester consumes from Kafka |

For Elasticsearch: use a dedicated index template for Jaeger, set `number_of_replicas: 1` in production, and configure ILM to roll and delete old indices automatically.

## Sampling Strategies

### Probabilistic sampling
```yaml
# jaeger-agent or remote-sampling config
sampling_strategies:
  default_strategy:
    type: probabilistic
    param: 0.01   # 1% of all traces
```

Use for high-traffic services where complete traces are impractical. Set 1–10% in production; 100% in development.

### Rate-limiting sampling
```yaml
default_strategy:
  type: ratelimiting
  param: 5   # max 5 traces per second per service instance
```

Provides stable trace volume regardless of traffic spikes. Good for SLO validation where you need consistent coverage.

### Remote (adaptive) sampling
```yaml
default_strategy:
  type: remote
  param: 0.001   # initial rate; Jaeger backend adjusts dynamically
```

Jaeger backend analyses trace data and adjusts per-operation sampling rates to maintain a target trace volume while prioritising slow/error traces. Requires Jaeger with a Sampling Store.

### Tail-based sampling (OTel Collector)
Configure in the OTel Collector `tailsampling` processor — Jaeger itself is not involved in the sampling decision:
```yaml
processors:
  tail_sampling:
    decision_wait: 10s
    policies:
      - name: errors
        type: status_code
        status_code: { status_codes: [ERROR] }
      - name: slow
        type: latency
        latency: { threshold_ms: 1000 }
      - name: probabilistic
        type: probabilistic
        probabilistic: { sampling_percentage: 1 }
```

## Span References

- **Child-of** (default): parent span depends on the child result — standard synchronous and async-with-wait relationships.
- **Follows-from**: parent span does not wait for child — use for fire-and-forget operations (async events, background jobs triggered by a request).

Jaeger UI renders both reference types; `follows-from` appears as a dashed line.

## Baggage Items

Jaeger propagates baggage via the `uberctx-{key}` header (Jaeger native) or the W3C `baggage` header (OTel). Baggage crosses service boundaries automatically.

Limits:
- Max key length: 256 bytes
- Max value length: 1,024 bytes
- Max total baggage size: 8 KB per span (use sparingly)

Never put PII, tokens, or secrets in baggage — it crosses service and network boundaries and may be logged by intermediaries.

## Jaeger UI Usage

- **Search**: filter by service, operation, tags, duration, and time range. Use tag queries (`error=true`, `http.status_code=500`) to find failed traces.
- **Trace timeline**: inspect span hierarchy, gaps between spans (network / queue latency), and span tags/logs.
- **Compare traces**: select two traces to diff — useful for before/after performance regression analysis.
- **Service dependencies**: auto-generated graph of inter-service call relationships.

## Performance

- Deploy Jaeger Collector behind a load balancer for high-throughput ingestion.
- Configure Collector `--collector.queue-size` and `--collector.num-workers` based on expected span volume.
- Use Kafka as an ingestion buffer for >10,000 spans/sec to absorb traffic spikes without dropping data.
- Set Elasticsearch retention via ILM: 7 days hot, 30 days warm, delete after 90 days (adjust to compliance requirements).
- Monitor `jaeger_collector_spans_received_total` and `jaeger_collector_spans_dropped_total` — alert if drop rate > 0.

## Security

- Restrict Jaeger UI (port 16686) to internal networks or add reverse-proxy authentication (OAuth2 proxy).
- Traces may contain sensitive operational data — apply the same access controls as logs.
- Use TLS between OTel Collector and Jaeger Collector for intra-cluster traffic leaving the trusted network.
- Sanitize span attributes before export: strip PII, request bodies with credentials, and auth tokens.

## Testing

- Use `jaeger-all-in-one` in Docker Compose for integration tests that assert trace structure.
- Assert that parent-child span relationships are correctly propagated across HTTP calls.
- Verify sampling: in rate-limited tests, confirm traces are created at the expected frequency.
- Use in-memory exporters for unit tests — Jaeger is an integration concern, not a unit test concern.

## Dos

- Use OTLP as the ingestion protocol in all new deployments.
- Deploy `jaeger-all-in-one` in Docker Compose for local development with zero configuration.
- Use adaptive sampling in production to automatically balance coverage and storage costs.
- Set `follows-from` references for fire-and-forget async spans.
- Configure Elasticsearch ILM for automatic index lifecycle management.

## Don'ts

- Don't use Jaeger Thrift/UDP protocol in new services — use OTLP instead.
- Don't expose Jaeger UI publicly without authentication — traces reveal internal architecture and call patterns.
- Don't use in-memory storage in production — data is lost on pod restart.
- Don't bypass the OTel Collector — routing directly from services to Jaeger removes buffering, retry, and sampling control.
- Don't put PII or credentials in span tags or baggage items.
- Don't set 100% probabilistic sampling in production for high-traffic services.
