# FastAPI + OpenTelemetry

> Extends `modules/observability/opentelemetry.md` with FastAPI-specific integration.
> Generic OTel conventions (context propagation, span naming, sampling, exporters) are NOT repeated here.

## Integration Setup

```bash
pip install \
  opentelemetry-sdk \
  opentelemetry-instrumentation-fastapi \
  opentelemetry-instrumentation-httpx \
  opentelemetry-instrumentation-sqlalchemy \
  opentelemetry-exporter-otlp-proto-grpc \
  prometheus-fastapi-instrumentator
```

Initialise the SDK in a dedicated module loaded before the application starts:

```python
# observability.py
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION
import os

def init_telemetry() -> None:
    resource = Resource.create({
        SERVICE_NAME: os.environ["SERVICE_NAME"],
        SERVICE_VERSION: os.environ.get("SERVICE_VERSION", "unknown"),
        "deployment.environment": os.environ.get("ENVIRONMENT", "development"),
    })
    otlp_endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317")

    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=otlp_endpoint)))
    trace.set_tracer_provider(tracer_provider)

    reader = PeriodicExportingMetricReader(OTLPMetricExporter(endpoint=otlp_endpoint))
    metrics.set_meter_provider(MeterProvider(resource=resource, metric_readers=[reader]))
```

Wire into the application entry point:

```python
# main.py
from fastapi import FastAPI
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from prometheus_fastapi_instrumentator import Instrumentator
from observability import init_telemetry

init_telemetry()

app = FastAPI()

# Auto-instrumentation: creates spans for every route
FastAPIInstrumentor.instrument_app(app)

# Prometheus metrics on /metrics
Instrumentator().instrument(app).expose(app, endpoint="/metrics")
```

## Framework-Specific Patterns

### Custom middleware for correlation ID propagation
```python
import uuid
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

class CorrelationIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        correlation_id = request.headers.get("X-Correlation-Id") or str(uuid.uuid4())
        request.state.correlation_id = correlation_id
        response = await call_next(request)
        response.headers["X-Correlation-Id"] = correlation_id
        return response

app.add_middleware(CorrelationIdMiddleware)
```

### Manual span creation
```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

@app.post("/orders")
async def create_order(order: OrderRequest):
    with tracer.start_as_current_span("order.validate") as span:
        span.set_attribute("order.items_count", len(order.items))
        span.set_attribute("order.total_cents", order.total_cents)
        validate_order(order)

    with tracer.start_as_current_span("order.persist") as span:
        result = await save_order(order)
        span.set_attribute("order.id", result.id)
        return result
```

### Custom Prometheus metrics
```python
from prometheus_client import Counter, Histogram

ORDER_COUNTER = Counter(
    "orders_created_total",
    "Total number of orders created",
    ["payment_method", "region"],
)
ORDER_AMOUNT = Histogram(
    "order_amount_cents",
    "Distribution of order amounts in cents",
    buckets=[100, 500, 1000, 5000, 10000, 50000, 100000],
)

@app.post("/orders")
async def create_order(order: OrderRequest):
    ORDER_COUNTER.labels(payment_method=order.payment_method, region=order.region).inc()
    ORDER_AMOUNT.observe(order.total_cents)
    …
```

### SQLAlchemy auto-instrumentation
```python
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
SQLAlchemyInstrumentor().instrument(engine=engine)
```

## Additional Dos

- Call `init_telemetry()` before creating the `FastAPI` app instance to ensure all SDK components are initialised.
- Use `FastAPIInstrumentor.instrument_app(app)` after app creation — it wraps the ASGI app.
- Pass `excluded_urls` to `FastAPIInstrumentor` to skip health check endpoints from trace noise: `excluded_urls="/health,/metrics"`.
- Use `prometheus-fastapi-instrumentator` for Prometheus metrics — it provides request duration histograms with sensible defaults.

## Additional Don'ts

- Don't initialise the SDK inside a route handler or dependency — it must run once at startup.
- Don't expose the `/metrics` Prometheus endpoint on the public API without network-level access control.
- Don't mix OTLP gRPC and HTTP exporters in the same process without explicit justification.
- Don't put PII or sensitive request data in span attributes.
