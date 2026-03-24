# ASP.NET Core + OpenTelemetry

> Extends `modules/observability/opentelemetry.md` with ASP.NET Core integration patterns.
> Generic OTel conventions (context propagation, span naming, sampling, exporters) are NOT repeated here.

## Integration Setup

```xml
<!-- .csproj -->
<PackageReference Include="OpenTelemetry.Extensions.Hosting" Version="1.*" />
<PackageReference Include="OpenTelemetry.Instrumentation.AspNetCore" Version="1.*" />
<PackageReference Include="OpenTelemetry.Instrumentation.Http" Version="1.*" />
<PackageReference Include="OpenTelemetry.Instrumentation.EntityFrameworkCore" Version="1.*" />
<PackageReference Include="OpenTelemetry.Exporter.OpenTelemetryProtocol" Version="1.*" />
<PackageReference Include="OpenTelemetry.Exporter.Prometheus.AspNetCore" Version="1.*-rc*" />
```

```csharp
// Program.cs
var otlpEndpoint = builder.Configuration["Otel:Endpoint"] ?? "http://otel-collector:4317";

builder.Services.AddOpenTelemetry()
    .ConfigureResource(r => r
        .AddService(
            serviceName: builder.Configuration["Service:Name"] ?? "unknown-service",
            serviceVersion: builder.Configuration["Service:Version"] ?? "0.0.0")
        .AddAttributes(new Dictionary<string, object>
        {
            ["deployment.environment"] = builder.Environment.EnvironmentName,
        }))
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation(o =>
        {
            o.RecordException = true;
            o.Filter = ctx => ctx.Request.Path != "/health";  // exclude health probes
        })
        .AddHttpClientInstrumentation(o => o.RecordException = true)
        .AddEntityFrameworkCoreInstrumentation(o => o.SetDbStatementForText = false) // avoid logging SQL with PII
        .AddSource(OrderService.ActivitySourceName)  // register custom ActivitySource
        .AddOtlpExporter(o => o.Endpoint = new Uri(otlpEndpoint)))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddRuntimeInstrumentation()
        .AddPrometheusExporter());   // exposes /metrics

// Expose /metrics endpoint
app.MapPrometheusScrapingEndpoint();
```

## Framework-Specific Patterns

### Manual spans with `ActivitySource`
.NET uses `System.Diagnostics.Activity` (the native tracing abstraction). OTel bridges it automatically.

```csharp
public class OrderService
{
    public const string ActivitySourceName = "OrderService";
    private static readonly ActivitySource Source = new(ActivitySourceName);

    public async Task<Order> CreateOrderAsync(CreateOrderRequest request)
    {
        using var activity = Source.StartActivity("order.create");
        activity?.SetTag("order.customer_id", request.CustomerId);
        activity?.SetTag("order.items_count", request.Items.Count);

        try
        {
            var order = await _repository.SaveAsync(Map(request));
            activity?.SetTag("order.id", order.Id.ToString());
            activity?.SetStatus(ActivityStatusCode.Ok);
            return order;
        }
        catch (Exception ex)
        {
            activity?.RecordException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            throw;
        }
    }
}
```

### Enriching auto-instrumented spans
```csharp
builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation(o =>
        {
            o.EnrichWithHttpRequest = (activity, request) =>
            {
                activity.SetTag("http.client_ip", request.HttpContext.Connection.RemoteIpAddress?.ToString());
                // Never set PII from request body here
            };
            o.EnrichWithHttpResponse = (activity, response) =>
            {
                activity.SetTag("http.response_content_type", response.ContentType);
            };
        }));
```

### Structured logging with trace context
Install `Serilog.Enrichers.OpenTelemetry` or use the built-in `ILogger` — .NET 9+ auto-injects `TraceId` and `SpanId` into `ILogger` scopes when OTel is configured:

```csharp
// Serilog approach
Log.Logger = new LoggerConfiguration()
    .Enrich.WithOpenTelemetryTraceId()
    .Enrich.WithOpenTelemetrySpanId()
    .WriteTo.Console(new JsonFormatter())
    .CreateLogger();
```

## Additional Dos

- Register your `ActivitySource` name with `AddSource(...)` — spans from unregistered sources are silently dropped.
- Set `RecordException = true` on HTTP instrumentation so exceptions are attached to spans automatically.
- Filter out health check paths from tracing to reduce noise: `o.Filter = ctx => !ctx.Request.Path.StartsWithSegments("/health")`.
- Use `SetDbStatementForText = false` for EF Core instrumentation in production to prevent SQL with parameter values (potential PII) from appearing in traces.

## Additional Don'ts

- Don't use `new Activity(...)` directly in new code — use `ActivitySource.StartActivity()` which honours the configured sampler.
- Don't set `SetDbStatementForText = true` in production if your queries contain user-supplied values.
- Don't expose `/metrics` on the public-facing port — restrict it to the internal management port.
- Don't put sensitive headers, request body content, or PII in span tags or enrichment callbacks.
