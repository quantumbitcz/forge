# Sentry — Observability Best Practices

## Overview
Sentry is an error tracking and performance monitoring platform providing real-time crash reporting, distributed tracing, and release health tracking. Use it for application-level error monitoring across web, mobile, and backend services. Sentry excels at grouping errors, providing stack traces with source maps, and tracking error rates per release. Avoid using it as a replacement for infrastructure monitoring (use Prometheus/Datadog) or log aggregation (use ELK/Loki).

## Architecture Patterns

**SDK initialization (Node.js):**
```javascript
import * as Sentry from "@sentry/node";

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  release: process.env.APP_VERSION,
  tracesSampleRate: process.env.NODE_ENV === "production" ? 0.1 : 1.0,
  profilesSampleRate: 0.1,
  integrations: [
    Sentry.httpIntegration(),
    Sentry.expressIntegration(),
    Sentry.prismaIntegration()
  ],
  beforeSend(event) {
    // Scrub PII
    if (event.user) delete event.user.email;
    return event;
  }
});
```

**SDK initialization (Python):**
```python
import sentry_sdk

sentry_sdk.init(
    dsn=os.environ["SENTRY_DSN"],
    environment=os.environ.get("ENV", "development"),
    release=os.environ.get("APP_VERSION"),
    traces_sample_rate=0.1,
    profiles_sample_rate=0.1,
    before_send=scrub_pii
)
```

**SDK initialization (Kotlin/JVM):**
```kotlin
Sentry.init { options ->
    options.dsn = System.getenv("SENTRY_DSN")
    options.environment = System.getenv("ENV") ?: "development"
    options.release = System.getenv("APP_VERSION")
    options.tracesSampleRate = 0.1
    options.isEnableAutoSessionTracking = true
}
```

**Custom context and breadcrumbs:**
```javascript
Sentry.setUser({ id: user.id });
Sentry.setTag("feature", "checkout");
Sentry.addBreadcrumb({ category: "payment", message: "Initiated payment", level: "info" });

try {
  await processPayment(order);
} catch (error) {
  Sentry.captureException(error, { extra: { orderId: order.id, amount: order.total } });
  throw error;
}
```

**Performance transactions:**
```javascript
const transaction = Sentry.startTransaction({ name: "POST /api/orders", op: "http.server" });
Sentry.configureScope(scope => scope.setSpan(transaction));

const span = transaction.startChild({ op: "db.query", description: "SELECT orders" });
const orders = await db.query("SELECT * FROM orders WHERE user_id = $1", [userId]);
span.finish();

transaction.finish();
```

**Anti-pattern — capturing expected errors as exceptions:** Don't send validation errors, 404s, or expected business logic errors to Sentry. They flood the error feed and obscure real issues. Use `beforeSend` to filter or use `Sentry.captureMessage` for informational events.

## Configuration

**Source maps (for JavaScript):**
```bash
# Upload source maps during CI/CD
npx @sentry/cli sourcemaps upload --release=$APP_VERSION ./dist
```

**Alert rules (Sentry UI or Terraform):**
```hcl
resource "sentry_issue_alert" "critical_errors" {
  organization = "my-org"
  project      = "backend"
  name         = "Critical error spike"

  conditions = [{ id = "sentry.rules.conditions.event_frequency.EventFrequencyCondition", value = 10, interval = "1h" }]
  actions    = [{ id = "sentry.integrations.slack.notify_action.SlackNotifyServiceAction", channel = "#alerts" }]
}
```

**Environment-specific sampling:**
```javascript
tracesSampleRate: process.env.NODE_ENV === "production" ? 0.1 : 1.0
```

## Performance

**Sample transactions in production:** 100% sampling generates enormous data volumes. Start with 1-10% (`tracesSampleRate: 0.01-0.1`) and increase for specific endpoints.

**Use `beforeSend` to reduce noise:**
```javascript
beforeSend(event) {
  if (event.exception?.values?.[0]?.type === "AxiosError" && event.exception.values[0].value.includes("ECONNRESET")) {
    return null;  // drop transient network errors
  }
  return event;
}
```

**Lazy SDK loading for frontend:**
```javascript
Sentry.init({ dsn: "...", integrations: [Sentry.replayIntegration({ maskAllText: true })],
  replaysSessionSampleRate: 0.1, replaysOnErrorSampleRate: 1.0 });
```

## Security

**Never include the Sentry DSN in client-visible logs** — while DSNs are designed for client-side use, avoid logging them to prevent abuse.

**Scrub PII in `beforeSend`:**
```javascript
beforeSend(event) {
  if (event.request?.headers) delete event.request.headers["authorization"];
  if (event.user) { delete event.user.email; delete event.user.ip_address; }
  return event;
}
```

**Use Sentry's data scrubbing rules** in project settings to automatically redact credit card numbers, passwords, and API keys.

**Configure allowed domains** in project settings to reject events from unauthorized origins.

## Testing

```javascript
// Test that errors are captured
import * as Sentry from "@sentry/node";

jest.mock("@sentry/node");

it("should capture payment errors", async () => {
  await expect(processPayment(invalidOrder)).rejects.toThrow();
  expect(Sentry.captureException).toHaveBeenCalledWith(
    expect.any(Error),
    expect.objectContaining({ extra: { orderId: invalidOrder.id } })
  );
});
```

Mock the Sentry SDK in unit tests — never send test errors to a real Sentry project. For integration tests, use a dedicated test Sentry project with relaxed rate limits.

## Dos
- Set `release` to your app version — Sentry uses it for release tracking, source maps, and regression detection.
- Use `beforeSend` to filter noise (expected errors, transient network issues) before they reach Sentry.
- Attach context (`setUser`, `setTag`, `addBreadcrumb`) to help triage errors without reproducing them.
- Upload source maps in CI/CD for readable stack traces in minified JavaScript.
- Use Sentry's issue assignment and ownership rules to route errors to the right team.
- Set appropriate sample rates — 100% tracing in production is prohibitively expensive.
- Use Sentry's release health to track crash-free sessions and error rates per deployment.

## Don'ts
- Don't capture expected errors (validation failures, 404s, auth denials) as exceptions — they flood the error feed.
- Don't set `tracesSampleRate: 1.0` in production — it generates enormous data volumes and increases costs.
- Don't log the Sentry DSN — it's designed for client use but shouldn't be discoverable in server logs.
- Don't skip `beforeSend` PII scrubbing — Sentry events can contain request headers, user data, and form inputs.
- Don't use Sentry as a log aggregation tool — use structured logging for operational logs, Sentry for errors.
- Don't ignore Sentry alerts — unresolved errors accumulate technical debt and mask new regressions.
- Don't capture errors in catch blocks that already handle the error gracefully — only report unexpected failures.
