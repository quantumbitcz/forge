# Django + OpenTelemetry

> Extends `modules/observability/opentelemetry.md` with Django-specific integration.
> Generic OTel conventions (context propagation, span naming, sampling, exporters) are NOT repeated here.

## Integration Setup

```bash
pip install \
  opentelemetry-sdk \
  opentelemetry-instrumentation-django \
  opentelemetry-instrumentation-psycopg2 \
  opentelemetry-instrumentation-requests \
  opentelemetry-exporter-otlp-proto-grpc \
  django-prometheus
```

Initialise the SDK in `manage.py` and `wsgi.py` / `asgi.py` **before** Django setup:

```python
# telemetry.py
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION
from opentelemetry.instrumentation.django import DjangoInstrumentor
from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
import os

def init_telemetry() -> None:
    resource = Resource.create({
        SERVICE_NAME: os.environ.get("SERVICE_NAME", "django-service"),
        SERVICE_VERSION: os.environ.get("SERVICE_VERSION", "unknown"),
        "deployment.environment": os.environ.get("DJANGO_ENV", "development"),
    })
    otlp_endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317")

    provider = TracerProvider(resource=resource)
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=otlp_endpoint)))
    trace.set_tracer_provider(provider)

    DjangoInstrumentor().instrument()
    Psycopg2Instrumentor().instrument()
    RequestsInstrumentor().instrument()
```

```python
# manage.py
from telemetry import init_telemetry
init_telemetry()

import django
# ... rest of manage.py
```

```python
# wsgi.py / asgi.py
from telemetry import init_telemetry
init_telemetry()

from django.core.wsgi import get_wsgi_application
application = get_wsgi_application()
```

## Framework-Specific Patterns

### Django settings integration
```python
# settings.py

MIDDLEWARE = [
    'django_prometheus.middleware.PrometheusBeforeMiddleware',
    # ... other middleware ...
    'django_prometheus.middleware.PrometheusAfterMiddleware',
]

INSTALLED_APPS = [
    # ...
    'django_prometheus',
]
```

```python
# urls.py
from django_prometheus import exports as prometheus_exports

urlpatterns = [
    path('', include('django_prometheus.urls')),  # exposes /metrics
    # ...
]
```

Restrict the `/metrics` route to internal networks via a reverse proxy or Django middleware.

### Manual spans in views / services
```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

class OrderCreateView(APIView):
    def post(self, request):
        with tracer.start_as_current_span("order.create") as span:
            span.set_attribute("order.items_count", len(request.data.get("items", [])))
            try:
                order = OrderService.create(request.data, user=request.user)
                span.set_attribute("order.id", str(order.id))
                return Response(OrderSerializer(order).data, status=201)
            except ValidationError as exc:
                span.record_exception(exc)
                span.set_status(trace.StatusCode.ERROR, str(exc))
                raise
```

### Excluding health check URLs from tracing
```python
# telemetry.py — pass excluded_urls to DjangoInstrumentor
DjangoInstrumentor().instrument(
    excluded_urls="health,metrics,favicon.ico",
)
```

### Trace context in structured logs
```python
# logging.py — custom filter to inject trace/span IDs
from opentelemetry import trace as otel_trace
import logging

class OtelTraceFilter(logging.Filter):
    def filter(self, record):
        span = otel_trace.get_current_span()
        ctx = span.get_span_context()
        record.trace_id = format(ctx.trace_id, '032x') if ctx.is_valid else ''
        record.span_id = format(ctx.span_id, '016x') if ctx.is_valid else ''
        return True
```

```python
# settings.py
LOGGING = {
    'filters': {'otel_trace': {'()': 'myapp.logging.OtelTraceFilter'}},
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'filters': ['otel_trace'],
            'formatter': 'json',
        }
    },
}
```

## Additional Dos

- Call `init_telemetry()` in both `manage.py` and `wsgi.py`/`asgi.py` — Django can be loaded via either path.
- Use `DjangoInstrumentor(excluded_urls=...)` to suppress traces for health and metrics endpoints.
- Use `Psycopg2Instrumentor` to capture database query spans automatically.
- Inject `trace_id` and `span_id` into Django's logging framework via a custom `logging.Filter` for log-trace correlation.

## Additional Don'ts

- Don't run `init_telemetry()` inside a Django `AppConfig.ready()` — it may run after WSGI/ASGI startup, missing the first requests.
- Don't expose `/metrics` on the public-facing URL conf without network-level protection.
- Don't instrument `requests` library when using `httpx` — use `opentelemetry-instrumentation-httpx` instead.
- Don't put Django `request.data` or `request.body` content in span attributes — it may contain PII or credentials.
