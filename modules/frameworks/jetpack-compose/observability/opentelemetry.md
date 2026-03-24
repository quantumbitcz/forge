# OpenTelemetry with Android + Jetpack Compose

## Integration Setup

```kotlin
// build.gradle.kts
implementation("io.opentelemetry.android:android-agent:0.7.0-alpha")
implementation("io.opentelemetry.android:instrumentation-okhttp:0.7.0-alpha")
implementation("io.opentelemetry.android:crash-plugin:0.7.0-alpha")
```

```kotlin
// Application.kt
class MyApp : Application() {
    lateinit var otelAndroid: OpenTelemetryAndroid

    override fun onCreate() {
        super.onCreate()
        otelAndroid = OpenTelemetryAndroid.builder(this)
            .addInstrumentation(OkHttpInstrumentation())
            .addPlugin(CrashReportingPlugin())
            .setResource(Resource.builder()
                .put(ResourceAttributes.SERVICE_NAME, "my-android-app")
                .put(ResourceAttributes.SERVICE_VERSION, BuildConfig.VERSION_NAME)
                .build())
            .setExporterEndpoint(BuildConfig.OTEL_ENDPOINT)
            .build()
    }
}
```

## Framework-Specific Patterns

### Manual Spans for Business Operations
```kotlin
fun processCheckout(cart: Cart) {
    val tracer = GlobalOpenTelemetry.getTracer("checkout-service")
    val span = tracer.spanBuilder("checkout.process")
        .setAttribute("cart.items_count", cart.items.size.toLong())
        .setAttribute("cart.total_cents", cart.totalCents)
        .startSpan()

    try {
        span.makeCurrent().use { /* business logic */ }
        span.setStatus(StatusCode.OK)
    } catch (e: Exception) {
        span.recordException(e)
        span.setStatus(StatusCode.ERROR)
        throw e
    } finally {
        span.end()
    }
}
```

### ANR and Crash Detection
```kotlin
// CrashReportingPlugin automatically bridges uncaught exceptions to OTel spans
// For ANR detection, add Android vitals plugin
otelAndroid = OpenTelemetryAndroid.builder(this)
    .addPlugin(SlowRenderingPlugin(slowThresholdMs = 16, frozenThresholdMs = 700))
    .build()
```

### Network Monitoring (OkHttp Instrumentation)
```kotlin
// OkHttpInstrumentation auto-instruments all OkHttp calls
// To add custom span attributes per request:
val client = OkHttpClient.Builder()
    .addInterceptor(OtelInterceptor(GlobalOpenTelemetry.getPropagators()))
    .build()
```

### Structured Logging Bridge
```kotlin
// Timber → OpenTelemetry Logs bridge
class OtelTimberTree : Timber.Tree() {
    private val logger = GlobalOpenTelemetry.get().logsBridge
        .get("timber").loggerBuilder("timber").build()

    override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
        val body = logger.logRecordBuilder()
            .setBody(message)
            .setSeverity(priority.toSeverity())
        t?.let { body.setAttribute(ExceptionAttributes.EXCEPTION_MESSAGE, it.message ?: "") }
        body.emit()
    }
}
```

## Scaffolder Patterns

```yaml
patterns:
  application: "MyApp.kt"
  tracer:      "observability/TelemetryService.kt"
```

## Additional Dos/Don'ts

- DO initialize OTel in `Application.onCreate()` before any other SDK
- DO use `OkHttpInstrumentation` to auto-capture all network spans without per-call boilerplate
- DO add `service.name` and `service.version` resource attributes for backend correlation
- DO capture ANR/slow rendering via `SlowRenderingPlugin` — these are invisible without instrumentation
- DON'T log PII (user names, emails, tokens) in span attributes or log bodies exported via OTLP
- DON'T use `AlwaysOnSampler` in production — use probability-based sampling (5-10% for high-traffic)
- DON'T export telemetry directly to a backend from the device in production; route through a collector proxy
