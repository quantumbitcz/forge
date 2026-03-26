# Datadog — Observability Best Practices

## Overview
Datadog is a full-stack observability platform providing infrastructure monitoring, APM (distributed tracing), log management, real-user monitoring (RUM), and synthetic tests. Use it when you need unified visibility across metrics, traces, and logs with automatic correlation. Datadog excels at large-scale infrastructure monitoring, service maps, and SLO tracking. Avoid it for cost-sensitive projects (per-host pricing scales linearly), simple applications where Prometheus + Grafana suffice, or when vendor lock-in is unacceptable.

## Architecture Patterns

**Datadog Agent deployment (Kubernetes):**
```yaml
# Helm values
datadog:
  apiKey: <DATADOG_API_KEY>
  site: datadoghq.com
  apm:
    portEnabled: true
  logs:
    enabled: true
    containerCollectAll: true
  processAgent:
    enabled: true
  networkMonitoring:
    enabled: true
```

**APM instrumentation (automatic — Node.js):**
```javascript
// dd-trace must be imported FIRST, before any other module
require("dd-trace").init({
  service: "order-service",
  env: process.env.NODE_ENV,
  version: process.env.APP_VERSION,
  logInjection: true,
  runtimeMetrics: true,
  profiling: true
});
```

**APM instrumentation (Python):**
```bash
# Auto-instrumentation via ddtrace-run
ddtrace-run python app.py
```
```python
# Or manual
from ddtrace import tracer
tracer.configure(hostname="datadog-agent", port=8126)

@tracer.wrap(service="order-service", resource="process_order")
def process_order(order_id: str):
    span = tracer.current_span()
    span.set_tag("order.id", order_id)
```

**APM instrumentation (Kotlin/JVM):**
```bash
# JVM agent
java -javaagent:/path/to/dd-java-agent.jar \
  -Ddd.service=order-service \
  -Ddd.env=production \
  -Ddd.version=1.2.3 \
  -Ddd.logs.injection=true \
  -jar app.jar
```

**Custom metrics (StatsD):**
```javascript
const StatsD = require("hot-shots");
const dogstatsd = new StatsD({ host: "datadog-agent", port: 8125, prefix: "myapp." });

dogstatsd.increment("orders.created", 1, { region: "us-east" });
dogstatsd.histogram("order.processing_time", durationMs, { service: "payments" });
dogstatsd.gauge("queue.depth", queueSize);
```

**Log correlation (automatic with `logInjection: true`):**
```javascript
// Logs automatically include dd.trace_id and dd.span_id
logger.info("Processing order", { orderId: order.id });
// Output: {"message":"Processing order","orderId":"123","dd.trace_id":"abc","dd.span_id":"def"}
```

**Anti-pattern — creating high-cardinality custom metrics with unbounded tag values:** Tags like `user_id` or `request_id` on custom metrics create millions of time series, causing cardinality explosions and massive cost increases. Use tags with bounded values (region, status, service).

## Configuration

**Unified tagging (across metrics, traces, logs):**
```yaml
# All Datadog data tagged with service, env, version
DD_SERVICE: order-service
DD_ENV: production
DD_VERSION: 1.2.3
DD_TAGS: team:payments,tier:critical
```

**Service Catalog (service metadata):**
```yaml
# service.datadog.yaml
schema-version: v2.1
dd-service: order-service
team: payments
contacts:
  - type: slack
    contact: "#payments-oncall"
integrations:
  pagerduty:
    service-url: https://pagerduty.com/services/ABC123
```

**SLO definitions:**
```hcl
resource "datadog_service_level_objective" "api_availability" {
  name = "API Availability"
  type = "metric"
  query {
    numerator   = "sum:http.requests.ok{service:order-service}.as_count()"
    denominator = "sum:http.requests.total{service:order-service}.as_count()"
  }
  thresholds {
    timeframe = "30d"
    target    = 99.9
    warning   = 99.95
  }
}
```

## Performance

**Sample traces in production:** Use head-based sampling (default) or Datadog's Ingestion Controls to keep costs predictable.
```javascript
require("dd-trace").init({
  ingestion: { sampleRate: 0.1 }  // 10% of traces
});
```

**Use tag-based metrics for dashboards** — avoid high-cardinality tags that explode time series count.

**Runtime metrics:** Enable automatic runtime metrics (GC, event loop, thread pool) for language-specific insights without custom instrumentation.

**Error tracking:** Let Datadog's error tracking group similar errors automatically — don't create custom metrics for every error type.

## Security

**API key management:** Store Datadog API keys in a secrets manager (AWS Secrets Manager, Vault), not in environment variables or config files.

**Sensitive data scrubbing:**
```yaml
# datadog.yaml
logs_config:
  processing_rules:
    - type: mask_sequences
      name: mask_credit_cards
      pattern: '\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b'
      replace_placeholder: '[REDACTED_CC]'
```

**Network security:** The Datadog Agent communicates outbound only (port 443). No inbound ports needed. Use a proxy for air-gapped environments.

**RBAC in Datadog:** Use teams and roles to restrict access to sensitive dashboards and logs.

## Testing

**Mock the StatsD client in tests:**
```javascript
jest.mock("hot-shots", () => ({
  StatsD: jest.fn().mockImplementation(() => ({
    increment: jest.fn(), histogram: jest.fn(), gauge: jest.fn()
  }))
}));
```

**Synthetic tests for uptime monitoring:**
```hcl
resource "datadog_synthetics_test" "api_health" {
  name    = "API Health Check"
  type    = "api"
  subtype = "http"
  request_definition {
    method = "GET"
    url    = "https://api.myapp.com/health"
  }
  assertion { type = "statusCode" operator = "is" target = "200" }
  locations = ["aws:us-east-1", "aws:eu-west-1"]
  options_list { tick_every = 60 }
}
```

Use Datadog's CI Test Visibility to track test performance over time. Don't send test metrics to production Datadog — use a separate org or exclude with `DD_TRACE_ENABLED=false`.

## Dos
- Use unified tagging (`DD_SERVICE`, `DD_ENV`, `DD_VERSION`) on all telemetry for automatic correlation.
- Enable log injection to correlate logs with APM traces automatically.
- Use Datadog's service catalog to document ownership, contacts, and runbooks per service.
- Define SLOs for critical services and set up burn-rate alerts.
- Use StatsD for custom business metrics (orders created, payments processed) with bounded tags.
- Configure sensitive data scrubbing for logs containing PII or credentials.
- Use Terraform/Pulumi to manage Datadog resources (monitors, dashboards, SLOs) as code.

## Don'ts
- Don't create custom metrics with high-cardinality tags (user_id, request_id) — they cause cardinality explosion and cost spikes.
- Don't set 100% trace sampling in production — use 1-10% sampling with ingestion controls.
- Don't hardcode Datadog API keys in source code — use a secrets manager.
- Don't ignore Datadog's cost estimation tools — custom metrics and log volume are the largest cost drivers.
- Don't use Datadog as a log archive — ship logs to S3/GCS for long-term retention and use Datadog for active querying.
- Don't skip the Service Catalog — without it, traces and metrics lack ownership context for incident response.
- Don't alert on raw metric values — use anomaly detection and SLO burn-rate alerts for meaningful notifications.
