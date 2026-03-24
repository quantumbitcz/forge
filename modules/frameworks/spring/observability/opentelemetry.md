# Spring Boot + OpenTelemetry

> Extends `modules/observability/opentelemetry.md` with Spring Boot tracing integration.
> Generic OTel conventions (SDK setup, context propagation, span naming, sampling) are NOT repeated here.

## Integration Setup

Spring Boot 3.x integrates OTel via Micrometer Tracing. Add the bridge and OTLP exporter:

```kotlin
// build.gradle.kts
implementation("org.springframework.boot:spring-boot-starter-actuator")
implementation("io.micrometer:micrometer-tracing-bridge-otel")
implementation("io.opentelemetry.exporter:opentelemetry-exporter-otlp")
```

```yaml
# application.yml
management:
  tracing:
    enabled: true
    sampling:
      probability: 0.1    # 10% head-based sampling; use 1.0 in dev
  otlp:
    tracing:
      endpoint: http://otel-collector:4318/v1/traces
      timeout: 10s
spring:
  application:
    name: order-service    # maps to service.name resource attribute
```

Auto-instrumentation covers:
- Incoming HTTP requests (WebMVC / WebFlux)
- Outgoing `RestClient` / `WebClient` calls
- Spring Data (JPA, R2DBC) — with `spring.jpa.open-in-view=false`
- Scheduled tasks (`@Scheduled`)
- Message listeners (Kafka, RabbitMQ via Spring Messaging)

### Java agent (alternative)
For full byte-code auto-instrumentation without dependency changes:
```dockerfile
ENTRYPOINT ["java",
  "-javaagent:/app/opentelemetry-javaagent.jar",
  "-Dotel.service.name=order-service",
  "-Dotel.exporter.otlp.endpoint=http://otel-collector:4317",
  "-jar", "/app/service.jar"]
```

Agent and Micrometer Tracing bridge should not be used simultaneously — pick one approach per service.

## Framework-Specific Patterns

### Manual span creation with `@WithSpan`
```kotlin
import io.micrometer.tracing.annotation.NewSpan
import io.micrometer.tracing.annotation.SpanTag

@Service
class PaymentService(private val tracer: Tracer) {

    @NewSpan("payment.authorize")
    fun authorizePayment(
        @SpanTag("payment.method") method: String,
        @SpanTag("payment.amount_cents") amountCents: Long,
    ): AuthResult { … }
}
```

`@NewSpan` creates a child span for the annotated method. `@SpanTag` maps method parameters to span attributes. Requires the `ObservationAOP` bean (auto-configured).

### Manual span via `Tracer` API
```kotlin
@Service
class OrderService(private val tracer: Tracer) {

    fun processOrder(order: Order): ProcessResult {
        val span = tracer.nextSpan().name("order.process").start()
        return tracer.withSpan(span).use {
            span.tag("order.id", order.id.toString())
            span.tag("order.items", order.items.size.toString())
            try {
                val result = doProcess(order)
                result
            } catch (e: Exception) {
                span.error(e)
                throw e
            }
        }
    }
}
```

### Propagating trace context to async tasks
```kotlin
@Configuration
class AsyncConfig(private val tracer: Tracer) : AsyncConfigurer {
    override fun getAsyncExecutor(): Executor =
        ContextPropagatingTaskDecorator()   // Micrometer's decorator propagates MDC + trace context
            .let { decorator ->
                ThreadPoolTaskExecutor().apply {
                    setTaskDecorator(decorator)
                    initialize()
                }
            }
}
```

### Trace ID in log output
Spring Boot 3.x auto-configures MDC fields `traceId` and `spanId` when Micrometer Tracing is on the classpath. Include them in your Logback/Log4j2 JSON layout:

```xml
<!-- logback-spring.xml (using logstash-logback-encoder) -->
<encoder class="net.logstash.logback.encoder.LogstashEncoder">
  <includeMdcKeyName>traceId</includeMdcKeyName>
  <includeMdcKeyName>spanId</includeMdcKeyName>
</encoder>
```

## Additional Dos

- Set `spring.application.name` — it maps directly to the OTel `service.name` resource attribute.
- Use `management.tracing.sampling.probability=1.0` in development for full trace visibility.
- Use `@NewSpan` for business-significant methods rather than low-level infrastructure calls.
- Route all exports through the OTel Collector — never send directly to Jaeger or Zipkin in production.
- Include `traceId` and `spanId` in structured log output for log-trace correlation.

## Additional Don'ts

- Don't use the Java OTel agent and Micrometer Tracing bridge simultaneously.
- Don't set `management.tracing.sampling.probability=1.0` in production for high-traffic services.
- Don't create spans for trivially fast operations (<1ms) that add overhead without insight.
- Don't put user IDs, request bodies, or PII in span tags — use opaque internal IDs.
