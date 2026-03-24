# Express + OpenTelemetry

> Extends `modules/observability/opentelemetry.md` with Express.js-specific integration.
> Generic OTel conventions (context propagation, span naming, sampling, exporters) are NOT repeated here.

## Integration Setup

```bash
npm install \
  @opentelemetry/sdk-node \
  @opentelemetry/auto-instrumentations-node \
  @opentelemetry/exporter-trace-otlp-grpc \
  @opentelemetry/exporter-metrics-otlp-grpc \
  @opentelemetry/resources \
  @opentelemetry/semantic-conventions \
  prom-client
```

Create a dedicated instrumentation entry point loaded **before** any application code:

```typescript
// tracing.ts  — must be loaded first via --require or NODE_OPTIONS
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-grpc';
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';
import { Resource } from '@opentelemetry/resources';
import { SEMRESATTRS_SERVICE_NAME, SEMRESATTRS_SERVICE_VERSION } from '@opentelemetry/semantic-conventions';

const sdk = new NodeSDK({
  resource: new Resource({
    [SEMRESATTRS_SERVICE_NAME]: process.env.SERVICE_NAME ?? 'unknown-service',
    [SEMRESATTRS_SERVICE_VERSION]: process.env.SERVICE_VERSION ?? '0.0.0',
    'deployment.environment': process.env.NODE_ENV ?? 'development',
  }),
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT ?? 'http://otel-collector:4317',
  }),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter({
      url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT ?? 'http://otel-collector:4317',
    }),
  }),
  instrumentations: [getNodeAutoInstrumentations({
    '@opentelemetry/instrumentation-fs': { enabled: false },   // noisy; disable unless needed
  })],
});

sdk.start();

process.on('SIGTERM', () => sdk.shutdown());
```

Load before the main module:
```json
// package.json
{
  "scripts": {
    "start": "node --require ./dist/tracing.js dist/app.js"
  }
}
```

## Framework-Specific Patterns

### prom-client for Prometheus metrics
```typescript
// metrics.ts
import { Registry, Counter, Histogram, collectDefaultMetrics } from 'prom-client';

export const registry = new Registry();
collectDefaultMetrics({ register: registry });

export const httpRequestsTotal = new Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [registry],
});

export const httpRequestDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
  registers: [registry],
});
```

### Express middleware for request metrics
```typescript
import { Request, Response, NextFunction } from 'express';
import { httpRequestsTotal, httpRequestDuration } from './metrics';

export function metricsMiddleware(req: Request, res: Response, next: NextFunction): void {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    const route = req.route?.path ?? req.path;
    const labels = { method: req.method, route, status_code: String(res.statusCode) };
    httpRequestsTotal.inc(labels);
    end(labels);
  });
  next();
}
```

### Metrics endpoint
```typescript
app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', registry.contentType);
  res.end(await registry.metrics());
});
```

### Manual span creation
```typescript
import { trace, SpanStatusCode } from '@opentelemetry/api';

const tracer = trace.getTracer('order-service', '1.0.0');

async function processOrder(order: Order): Promise<ProcessResult> {
  return tracer.startActiveSpan('order.process', async (span) => {
    span.setAttributes({
      'order.id': order.id,
      'order.items_count': order.items.length,
      'order.total_cents': order.totalCents,
    });
    try {
      const result = await doProcess(order);
      span.setStatus({ code: SpanStatusCode.OK });
      return result;
    } catch (err) {
      span.recordException(err as Error);
      span.setStatus({ code: SpanStatusCode.ERROR, message: (err as Error).message });
      throw err;
    } finally {
      span.end();
    }
  });
}
```

## Additional Dos

- Always load `tracing.ts` via `--require` before any other module — OTel SDK must initialise before `http`, `express`, and database modules are imported.
- Disable noisy auto-instrumentations (`fs`, `dns`) that produce high span volume without actionable insight.
- Use `prom-client` `collectDefaultMetrics()` to expose Node.js process metrics (heap, GC, event loop lag) automatically.
- Normalise route labels in the metrics middleware to use `req.route?.path` (Express named route) rather than `req.path` (prevents high-cardinality explosion from path parameters).

## Additional Don'ts

- Don't import `tracing.ts` from `app.ts` — use `--require` to guarantee it loads first, before any instrumented modules.
- Don't expose `/metrics` on the same port as the public API in production — use a separate internal port or restrict via middleware.
- Don't use `req.path` as a metric label for parameterised routes — it includes the actual parameter value and causes cardinality explosion.
- Don't put user session data or request bodies in span attributes.
