# Grafana Loki — Log Aggregation Best Practices

## Overview

Grafana Loki is a log aggregation system designed for cost-efficiency by indexing only labels
(metadata), not the full log content. Use it for application log aggregation, especially alongside
Prometheus and Grafana in the "PLG" stack (Promtail/Loki/Grafana). Loki excels at correlating logs
with metrics via shared labels. Avoid it for full-text search over logs (use Elasticsearch), complex
log analytics with aggregations, or when you need sub-second query latency on large datasets.

## Architecture Patterns

### Label Design (Critical for Performance)
```yaml
# Promtail config — labels define how logs are indexed
scrape_configs:
  - job_name: kubernetes
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_label_app]
        target_label: app
      - source_labels: [__meta_kubernetes_container_name]
        target_label: container
```

### LogQL Queries
```logql
# Filter by label and content
{app="order-service", namespace="production"} |= "error" | json | status >= 500

# Rate of errors per minute
rate({app="order-service"} |= "error" [1m])

# Top 5 error messages
topk(5, sum by (message) (rate({app="order-service"} | json | level="error" [5m])))

# Metric from logs (histogram of response times)
histogram_quantile(0.99, sum by (le) (
  rate({app="order-service"} | json | unwrap response_time_ms [5m])
))
```

### Structured Logging (Application Side)
```javascript
// JSON structured logs — Loki parses them with | json
logger.info({ orderId: "123", userId: "456", amount: 99.99, action: "order_created" });
// Output: {"level":"info","orderId":"123","userId":"456","amount":99.99,"action":"order_created","timestamp":"..."}
```

### Anti-pattern — using high-cardinality labels: Labels like `user_id`, `request_id`, or `trace_id` create millions of streams, degrading Loki's performance and increasing storage costs. Use log content filtering (`|=`, `| json`) instead.

## Configuration

```yaml
# Loki config
auth_enabled: false
server:
  http_listen_port: 3100

schema_config:
  configs:
    - from: 2026-01-01
      store: tsdb
      object_store: s3
      schema: v13
      index:
        prefix: loki_index_
        period: 24h

storage_config:
  aws:
    s3: s3://region/bucket-name
    region: us-east-1

limits_config:
  retention_period: 30d
  max_query_length: 721h
  max_streams_per_user: 10000
```

## Dos
- Use low-cardinality labels only (service, environment, namespace, level) — labels drive Loki's index.
- Use structured JSON logging — Loki's `| json` parser extracts fields at query time.
- Correlate logs with traces by including `trace_id` in log content (not labels) — query with `|= "trace_id=..."`.
- Use `rate()` on log queries for metrics-from-logs — useful for error rate tracking without custom metrics.
- Use Promtail, Alloy, or FluentBit for log shipping — they integrate natively with Loki.
- Set retention policies to control storage costs — Loki can retain logs for days to months.
- Use recording rules for frequently queried LogQL expressions.

## Don'ts
- Don't use high-cardinality labels (user_id, request_id, IP address) — they create too many streams.
- Don't use Loki for full-text search across millions of logs — it's optimized for label-filtered log retrieval.
- Don't skip structured logging — unstructured text logs require expensive regex parsing.
- Don't query without label filters — `{} |= "error"` scans all streams and is extremely slow.
- Don't ignore chunk and stream limits — exceeding `max_streams_per_user` causes ingestion failures.
- Don't use Loki as a database — it's append-only, designed for time-series log data.
- Don't mix application logs with infrastructure logs in the same tenant without label separation.
