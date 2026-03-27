# Docker with Spring

> Extends `modules/container-orchestration/docker.md` with Spring Boot containerization patterns.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

### Layered JAR Dockerfile

```dockerfile
# Stage 1: Extract layers from Spring Boot fat JAR
FROM eclipse-temurin:21-jre-alpine AS extract
WORKDIR /app
COPY build/libs/*.jar app.jar
RUN java -Djarmode=layertools -jar app.jar extract

# Stage 2: Build the runtime image
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# Create non-root user
RUN addgroup -S spring && adduser -S spring -G spring

# Copy layers in order of change frequency (least to most)
COPY --from=extract /app/dependencies/ ./
COPY --from=extract /app/spring-boot-loader/ ./
COPY --from=extract /app/snapshot-dependencies/ ./
COPY --from=extract /app/application/ ./

USER spring:spring

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD wget -qO- http://localhost:8080/actuator/health/liveness || exit 1

ENTRYPOINT ["java", \
    "-XX:MaxRAMPercentage=75", \
    "-XX:+UseG1GC", \
    "-XX:+UseContainerSupport", \
    "org.springframework.boot.loader.launch.JarLauncher"]
```

The `jarmode=layertools` extracts the fat JAR into four layers. Dependencies change rarely, so Docker caches them independently from application code.

## Framework-Specific Patterns

### JVM Container Tuning

```dockerfile
ENTRYPOINT ["java", \
    "-XX:MaxRAMPercentage=75", \
    "-XX:InitialRAMPercentage=50", \
    "-XX:+UseG1GC", \
    "-XX:+UseContainerSupport", \
    "-XX:+ExitOnOutOfMemoryError", \
    "-Djava.security.egd=file:/dev/urandom", \
    "org.springframework.boot.loader.launch.JarLauncher"]
```

Key flags:
- `MaxRAMPercentage=75` -- leave headroom for off-heap (Netty buffers, native memory)
- `UseContainerSupport` -- JVM respects cgroup memory limits (default since JDK 10, but explicit is safer)
- `ExitOnOutOfMemoryError` -- let the orchestrator restart rather than run in a degraded state

### Spring Boot Actuator as HEALTHCHECK

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD wget -qO- http://localhost:8080/actuator/health/liveness || exit 1
```

```yaml
# application.yml
management:
  endpoint:
    health:
      probes:
        enabled: true
  health:
    livenessState:
      enabled: true
    readinessState:
      enabled: true
```

Use `/actuator/health/liveness` for Docker HEALTHCHECK. The `start-period` should exceed your application's startup time.

### Distroless Base Image

```dockerfile
FROM gcr.io/distroless/java21-debian12
WORKDIR /app
COPY --from=extract /app/dependencies/ ./
COPY --from=extract /app/spring-boot-loader/ ./
COPY --from=extract /app/snapshot-dependencies/ ./
COPY --from=extract /app/application/ ./
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "org.springframework.boot.loader.launch.JarLauncher"]
```

Distroless images have no shell, package manager, or OS utilities -- smaller attack surface. Trade-off: no `wget` for HEALTHCHECK; rely on orchestrator probes instead.

### Spring Boot Docker Compose Support

```kotlin
// build.gradle.kts
dependencies {
    developmentOnly("org.springframework.boot:spring-boot-docker-compose")
}
```

```yaml
# compose.yaml (auto-detected by Spring Boot)
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: secret
    ports:
      - "5432:5432"
```

Spring Boot 3.1+ auto-detects `compose.yaml` at project root, starts services on boot, and injects connection properties. Disable in production with `spring.docker.compose.enabled=false`.

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
  compose_dev: "compose.yaml"
```

## Additional Dos

- DO use Spring Boot's `jarmode=layertools` for optimal Docker layer caching
- DO set `MaxRAMPercentage=75` to leave room for off-heap memory in containers
- DO use `start-period` in HEALTHCHECK to accommodate Spring Boot startup time
- DO use `spring-boot-docker-compose` for local development with automatic service lifecycle

## Additional Don'ts

- DON'T use `java -jar app.jar` -- use `JarLauncher` with extracted layers for layer caching
- DON'T set `-Xmx` in containers -- use `-XX:MaxRAMPercentage` to adapt to the container memory limit
- DON'T include DevTools or `spring-boot-docker-compose` in production images
- DON'T run as root -- create a `spring` user and switch to it before ENTRYPOINT
