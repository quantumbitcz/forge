# NestJS + OpenTelemetry

> NestJS-specific patterns for observability with `@opentelemetry/sdk-node`.
> Extends generic NestJS conventions.

## Integration Setup

```bash
npm install \
  @opentelemetry/sdk-node \
  @opentelemetry/auto-instrumentations-node \
  @opentelemetry/exporter-trace-otlp-grpc \
  @opentelemetry/exporter-metrics-otlp-grpc \
  @opentelemetry/resources \
  @opentelemetry/semantic-conventions \
  @opentelemetry/instrumentation-nestjs-core \
  prom-client
```

## Instrumentation Entry Point

Create a dedicated file loaded **before** any application code via `--require`:

```typescript
// src/tracing.ts — must be the first module loaded
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { NestInstrumentation } from '@opentelemetry/instrumentation-nestjs-core';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-grpc';
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';
import { Resource } from '@opentelemetry/resources';
import {
  SEMRESATTRS_SERVICE_NAME,
  SEMRESATTRS_SERVICE_VERSION,
} from '@opentelemetry/semantic-conventions';

const sdk = new NodeSDK({
  resource: new Resource({
    [SEMRESATTRS_SERVICE_NAME]: process.env.SERVICE_NAME ?? 'nestjs-service',
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
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': { enabled: false },
    }),
    new NestInstrumentation(),   // adds NestJS-specific span attributes (controller, handler names)
  ],
});

sdk.start();
process.on('SIGTERM', () => sdk.shutdown());
```

`package.json`:
```json
{
  "scripts": {
    "start": "node --require ./dist/tracing.js dist/main.js"
  }
}
```

## NestJS Logger Integration

Replace the default NestJS logger with a structured logger that emits trace context:

```typescript
// src/common/logger/otel-logger.service.ts
import { LoggerService, Injectable } from '@nestjs/common';
import { trace, context } from '@opentelemetry/api';
import * as pino from 'pino';

@Injectable()
export class OtelLoggerService implements LoggerService {
  private readonly pino = pino.default({
    level: process.env.LOG_LEVEL ?? 'info',
    formatters: { level: (label) => ({ level: label }) },
  });

  log(message: string, context?: string): void {
    this.pino.info({ context, ...this.traceContext() }, message);
  }

  error(message: string, trace?: string, context?: string): void {
    this.pino.error({ context, trace, ...this.traceContext() }, message);
  }

  warn(message: string, context?: string): void {
    this.pino.warn({ context, ...this.traceContext() }, message);
  }

  private traceContext() {
    const span = trace.getActiveSpan();
    if (!span) return {};
    const { traceId, spanId } = span.spanContext();
    return { traceId, spanId };
  }
}
```

Register in `main.ts`:
```typescript
const app = await NestFactory.create(AppModule, { bufferLogs: true });
app.useLogger(app.get(OtelLoggerService));
```

## Prometheus Metrics Endpoint

```typescript
// src/metrics/metrics.module.ts
import { collectDefaultMetrics, Registry, Counter, Histogram } from 'prom-client';

@Module({})
export class MetricsModule implements OnModuleInit {
  static registry = new Registry();

  static httpRequestsTotal = new Counter({
    name: 'http_requests_total',
    help: 'Total HTTP requests',
    labelNames: ['method', 'route', 'status_code'],
    registers: [MetricsModule.registry],
  });

  static httpDuration = new Histogram({
    name: 'http_request_duration_seconds',
    help: 'HTTP request duration',
    labelNames: ['method', 'route', 'status_code'],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
    registers: [MetricsModule.registry],
  });

  onModuleInit(): void {
    collectDefaultMetrics({ register: MetricsModule.registry });
  }
}

// Metrics endpoint (on internal port or with IP restriction)
@Controller('metrics')
export class MetricsController {
  @Get()
  async metrics(@Res() res: Response): Promise<void> {
    res.set('Content-Type', MetricsModule.registry.contentType);
    res.end(await MetricsModule.registry.metrics());
  }
}
```

## Manual Span Creation in Services

```typescript
import { trace, SpanStatusCode } from '@opentelemetry/api';

@Injectable()
export class OrdersService {
  private readonly tracer = trace.getTracer('orders-service', '1.0.0');

  async processOrder(order: Order): Promise<ProcessResult> {
    return this.tracer.startActiveSpan('orders.process', async (span) => {
      span.setAttributes({
        'order.id': order.id,
        'order.items_count': order.items.length,
        'order.total_cents': order.totalCents,
      });
      try {
        const result = await this.doProcess(order);
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
}
```

## Scaffolder Patterns

```
src/
  tracing.ts                             # OTel SDK init — loaded via --require
  common/
    logger/
      otel-logger.service.ts             # Structured logger with trace context
  metrics/
    metrics.module.ts                    # prom-client setup + /metrics endpoint
    metrics.controller.ts
```

## Dos

- Load `tracing.ts` via `--require` before `main.js` — SDK must initialize before NestJS imports `http`, `pg`, etc.
- Use `NestInstrumentation` to get NestJS-aware span names (includes controller + handler context)
- Emit trace context (`traceId`, `spanId`) in every log line for correlation with traces
- Expose `/metrics` on a separate internal port or behind IP-based middleware in production

## Don'ts

- Don't import `tracing.ts` from `main.ts` — use `--require` to guarantee load order
- Don't expose `/metrics` on the public API port in production without access control
- Don't include user PII or request bodies in span attributes
- Don't disable `NestInstrumentation` — it provides controller/handler span naming critical for debugging
