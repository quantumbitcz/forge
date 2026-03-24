# Spring Boot + Micrometer

> Extends `modules/observability/micrometer.md` with Spring Boot Actuator integration.
> Generic Micrometer conventions (meter types, naming, cardinality, tagging) are NOT repeated here.

## Integration Setup

Spring Boot auto-configures Micrometer via `spring-boot-starter-actuator`. Add the Prometheus registry for scraping:

```kotlin
// build.gradle.kts
implementation("org.springframework.boot:spring-boot-starter-actuator")
implementation("io.micrometer:micrometer-registry-prometheus")
```

```yaml
# application.yml
management:
  endpoints:
    web:
      exposure:
        include: health, info, prometheus, metrics
      base-path: /actuator
  endpoint:
    health:
      show-details: when-authorized
      probes:
        enabled: true      # exposes /actuator/health/liveness and /actuator/health/readiness
  metrics:
    tags:
      application: ${spring.application.name}
      environment: ${spring.profiles.active:development}
    distribution:
      percentiles-histogram:
        http.server.requests: true
      slo:
        http.server.requests: 100ms, 500ms, 1s
```

Bind Kubernetes probes to the Actuator liveness/readiness endpoints:
```yaml
livenessProbe:
  httpGet:
    path: /actuator/health/liveness
    port: 8080
readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: 8080
```

## Framework-Specific Patterns

### `@Timed` annotation
```kotlin
@Service
class OrderService(private val meterRegistry: MeterRegistry) {

    @Timed(
        value = "orders.create",
        histogram = true,
        percentiles = [0.5, 0.95, 0.99],
        extraTags = ["layer", "service"],
    )
    fun createOrder(request: CreateOrderRequest): Order { … }
}
```

Requires `TimedAspect` bean — not registered automatically:
```kotlin
@Configuration
class MetricsConfig {
    @Bean
    fun timedAspect(registry: MeterRegistry) = TimedAspect(registry)

    @Bean
    fun countedAspect(registry: MeterRegistry) = CountedAspect(registry)
}
```

### Custom `MeterBinder`
```kotlin
@Component
class OrderQueueMetrics(private val orderQueue: OrderQueue) : MeterBinder {
    override fun bindTo(registry: MeterRegistry) {
        Gauge.builder("order.queue.depth", orderQueue) { it.size().toDouble() }
            .description("Current number of pending orders in processing queue")
            .register(registry)
    }
}
```

Spring auto-discovers `MeterBinder` beans and calls `bindTo` at startup.

### Composite registry for multiple backends
```kotlin
@Bean
fun compositeMeterRegistry(
    prometheusRegistry: PrometheusMeterRegistry,
    datadogRegistry: DatadogMeterRegistry,
): CompositeMeterRegistry = CompositeMeterRegistry().apply {
    add(prometheusRegistry)
    add(datadogRegistry)
}
```

### R2DBC / reactive metrics
Auto-configured by `spring-boot-starter-data-r2dbc` when Micrometer is on the classpath. Meter names follow `r2dbc.pool.*`. Enable with:
```yaml
management.metrics.enable.r2dbc: true
```

### Custom HTTP request tags
```kotlin
@Bean
fun webMvcTagsContributor() = WebMvcTagsContributor { _, _, _, _ ->
    Tags.of("api_version", "v2")
}
```

## Additional Dos

- Use `management.endpoints.web.base-path` consistently — default `/actuator` is fine, but customise the port for internal-only exposure.
- Enable `probes.enabled: true` to get dedicated `/health/liveness` and `/health/readiness` endpoints for Kubernetes.
- Add `application` and `environment` common tags at the management level — Spring Boot sets them on all meters automatically.
- Use `slo:` distribution config to get precise SLO bucket alignment in Prometheus histograms.

## Additional Don'ts

- Don't expose the `/actuator/prometheus` endpoint on the public-facing port — use a separate `management.server.port`.
- Don't enable all actuator endpoints (`include: "*"`) in production — expose only `health`, `prometheus`, `info`.
- Don't use `@Timed` without registering `TimedAspect` — it silently does nothing.
- Don't rely on Spring's default `http.server.requests` histogram alone for SLO alerting — configure `slo:` buckets at the SLO threshold.
