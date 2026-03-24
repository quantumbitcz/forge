# Go stdlib + OpenTelemetry

> Go net/http OTel patterns. Extends generic Go conventions.
> Generic OTel conventions (context propagation, span naming, sampling) are NOT repeated here.

## Integration Setup

```go
// go.mod
require (
    go.opentelemetry.io/otel v1.28.0
    go.opentelemetry.io/otel/trace v1.28.0
    go.opentelemetry.io/otel/sdk v1.28.0
    go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.28.0
    go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.53.0
    github.com/prometheus/client_golang v1.20.0
)
```

## TracerProvider Initialization

```go
func InitTelemetry(ctx context.Context, serviceName, serviceVersion, otlpEndpoint string) (func(), error) {
    res, _ := resource.Merge(
        resource.Default(),
        resource.NewWithAttributes(semconv.SchemaURL,
            semconv.ServiceName(serviceName),
            semconv.ServiceVersion(serviceVersion),
        ),
    )

    exporter, err := otlptracegrpc.New(ctx,
        otlptracegrpc.WithEndpoint(otlpEndpoint),
        otlptracegrpc.WithInsecure(),
    )
    if err != nil {
        return nil, fmt.Errorf("otlp exporter: %w", err)
    }

    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(exporter),
        sdktrace.WithResource(res),
        sdktrace.WithSampler(sdktrace.ParentBased(sdktrace.TraceIDRatioBased(0.1))),
    )
    otel.SetTracerProvider(tp)
    otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
        propagation.TraceContext{}, propagation.Baggage{},
    ))

    return func() {
        ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
        defer cancel()
        _ = tp.Shutdown(ctx)
    }, nil
}
```

## Auto-Instrumentation for net/http

```go
import "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

// Wrap entire mux — all routes get automatic spans
handler := otelhttp.NewHandler(mux, "http-server",
    otelhttp.WithMessageEvents(otelhttp.ReadEvents, otelhttp.WriteEvents),
)

srv := &http.Server{
    Addr:    ":8080",
    Handler: handler,
}
```

## Manual Spans in Handlers

```go
func createOrderHandler(svc OrderService) http.HandlerFunc {
    tracer := otel.Tracer("orders")
    return func(w http.ResponseWriter, r *http.Request) {
        ctx, span := tracer.Start(r.Context(), "order.create",
            trace.WithAttributes(
                attribute.String("http.method", r.Method),
            ),
        )
        defer span.End()

        order, err := svc.Create(ctx, ...)
        if err != nil {
            span.RecordError(err)
            span.SetStatus(codes.Error, err.Error())
            writeError(w, http.StatusInternalServerError, "create failed")
            return
        }
        span.SetAttributes(attribute.String("order.id", order.ID))
        writeJSON(w, http.StatusCreated, order)
    }
}
```

## Prometheus Exporter

```go
import "github.com/prometheus/client_golang/prometheus/promhttp"

// Mount on a separate port to keep metrics internal
metricsMux := http.NewServeMux()
metricsMux.Handle("/metrics", promhttp.Handler())
go http.ListenAndServe(":9090", metricsMux)
```

## Scaffolder Patterns

```yaml
patterns:
  telemetry_init: "internal/telemetry/telemetry.go"
  server_wrap: "internal/server/server.go"    # otelhttp.NewHandler applied here
  metrics_server: "internal/telemetry/metrics.go"
```

## Additional Dos/Don'ts

- DO call the shutdown function (returned by `InitTelemetry`) on `SIGTERM` to flush the batch exporter
- DO wrap the top-level `http.Handler` with `otelhttp.NewHandler` once — avoid per-route wrapping
- DO use `span.RecordError(err)` and `span.SetStatus(codes.Error, ...)` together on failures
- DO expose Prometheus `/metrics` on a separate port not reachable from the internet
- DON'T record user-submitted request body content in span attributes — use opaque IDs
- DON'T set sampler to `AlwaysSample` in production under load — use ratio-based or parent-based sampling
- DON'T call `otel.SetTracerProvider` more than once — initialize once at startup
