# Next.js + OpenTelemetry

> Distributed tracing for Next.js using `@vercel/otel` (recommended) or manual OTEL SDK setup.
> Next.js requires an `instrumentation.ts` file at the project root (or `src/`) to initialize OTEL.

## Integration Setup

```bash
# Option A: Vercel-hosted (simplest)
npm install @vercel/otel

# Option B: Manual (self-hosted / custom collector)
npm install @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node \
  @opentelemetry/exporter-trace-otlp-http
```

Enable the instrumentation hook in `next.config.ts`:
```typescript
const nextConfig = { experimental: { instrumentationHook: true } };
export default nextConfig;
```

## Framework-Specific Patterns

### `instrumentation.ts` — Vercel OTEL
```typescript
// instrumentation.ts
import { registerOTel } from '@vercel/otel';

export function register() {
  registerOTel({ serviceName: process.env.OTEL_SERVICE_NAME ?? 'my-app' });
}
```

### `instrumentation.ts` — Manual SDK
```typescript
// instrumentation.ts
export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    const { NodeSDK } = await import('@opentelemetry/sdk-node');
    const { OTLPTraceExporter } = await import('@opentelemetry/exporter-trace-otlp-http');
    const { getNodeAutoInstrumentations } = await import('@opentelemetry/auto-instrumentations-node');

    const sdk = new NodeSDK({
      traceExporter: new OTLPTraceExporter({ url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT }),
      instrumentations: [getNodeAutoInstrumentations()],
    });
    sdk.start();
  }
}
```

### Custom spans in Server Components / Route Handlers
```typescript
import { trace } from '@opentelemetry/api';

const tracer = trace.getTracer('my-app');

export async function fetchUser(id: string) {
  return tracer.startActiveSpan('db.fetchUser', async (span) => {
    try {
      span.setAttribute('user.id', id);
      return await prisma.user.findUnique({ where: { id } });
    } finally {
      span.end();
    }
  });
}
```

### Edge runtime note
OTEL SDK does not run on the Edge runtime. Gate SDK init with `process.env.NEXT_RUNTIME === 'nodejs'` (as shown above). Edge-compatible tracing requires `@vercel/otel` with Vercel's infrastructure.

## Scaffolder Patterns
```
instrumentation.ts            # OTEL registration (project root or src/)
lib/
  telemetry.ts                # tracer factory + custom span helpers
next.config.ts                # experimentalInstrumentationHook: true
```

## Dos
- Guard all OTEL init with `NEXT_RUNTIME === 'nodejs'` to avoid edge runtime crashes
- Use `startActiveSpan` with a `finally { span.end() }` to ensure spans always close
- Set `OTEL_SERVICE_NAME` and `OTEL_EXPORTER_OTLP_ENDPOINT` via environment variables
- Add `db.statement`, `http.route`, and `user.id` attributes for useful traces

## Don'ts
- Don't call OTEL SDK APIs in Client Components — tracing is server-side only
- Don't initialize the SDK outside `instrumentation.ts` — Next.js may call it multiple times
- Don't hardcode the OTLP endpoint; always use env vars for portability
- Don't add spans to every function — instrument boundaries (DB, HTTP, queue) not internals
