# Gin + OpenTelemetry

> Gin-specific OTel patterns using `otelgin` middleware.
> Generic OTel and TracerProvider setup are in `modules/frameworks/go-stdlib/observability/opentelemetry.md`.

## Integration Setup

```go
// go.mod
require (
    github.com/gin-gonic/gin v1.10.0
    go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin v0.53.0
    github.com/prometheus/client_golang v1.20.0
)
```

## otelgin Middleware

```go
import "go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"

func setupRouter(serviceName string) *gin.Engine {
    r := gin.New()

    // otelgin creates a span per request with route, method, status code attributes
    r.Use(otelgin.Middleware(serviceName,
        otelgin.WithFilter(func(req *http.Request) bool {
            // Skip health check and metrics endpoints
            return req.URL.Path != "/health" && req.URL.Path != "/metrics"
        }),
    ))
    r.Use(gin.Recovery())

    return r
}
```

## Custom Spans in Handlers

```go
func CreateOrderHandler(svc OrderService) gin.HandlerFunc {
    tracer := otel.Tracer("orders")
    return func(c *gin.Context) {
        ctx, span := tracer.Start(c.Request.Context(), "order.create",
            trace.WithAttributes(
                attribute.String("user.id", c.GetString("user_id")),
            ),
        )
        defer span.End()

        var req CreateOrderRequest
        if err := c.ShouldBindJSON(&req); err != nil {
            span.SetStatus(codes.Error, "invalid request")
            c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
            return
        }

        order, err := svc.Create(ctx, req)
        if err != nil {
            span.RecordError(err)
            span.SetStatus(codes.Error, err.Error())
            c.JSON(http.StatusInternalServerError, gin.H{"error": "create failed"})
            return
        }

        span.SetAttributes(attribute.String("order.id", order.ID))
        c.JSON(http.StatusCreated, order)
    }
}
```

## Prometheus Metrics

```go
import "github.com/prometheus/client_golang/prometheus/promhttp"

// Expose on a separate port, not the main API port
go func() {
    metricsMux := http.NewServeMux()
    metricsMux.Handle("/metrics", promhttp.Handler())
    http.ListenAndServe(":9090", metricsMux)
}()
```

For per-endpoint Gin metrics, use `github.com/zsais/go-gin-prometheus` alongside otelgin.

## Scaffolder Patterns

```yaml
patterns:
  telemetry_init: "internal/telemetry/telemetry.go"
  router_setup: "internal/server/router.go"   # otelgin.Middleware applied here
  metrics_server: "internal/telemetry/metrics.go"
```

## Additional Dos/Don'ts

- DO apply `otelgin.Middleware` before `gin.Recovery()` so panics are recorded in the span before recovery
- DO use the `WithFilter` option to exclude health/readiness probes from trace noise
- DO call `span.RecordError(err)` before returning error JSON responses — links the error to the span
- DO expose Prometheus `/metrics` on a dedicated internal port (9090), not the public API port (8080)
- DON'T use `context.Background()` when starting child spans in handlers — always use `c.Request.Context()`
- DON'T record user-supplied request body fields in span attributes — use opaque correlation IDs
