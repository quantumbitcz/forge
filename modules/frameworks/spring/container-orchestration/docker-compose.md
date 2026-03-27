# Docker Compose with Spring

> Extends `modules/container-orchestration/docker-compose.md` with Spring Boot service composition patterns.
> Generic Docker Compose conventions (service definitions, networking, volumes) are NOT repeated here.

## Integration Setup

```yaml
# compose.yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      SPRING_PROFILES_ACTIVE: local
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/app
      SPRING_DATASOURCE_USERNAME: app
      SPRING_DATASOURCE_PASSWORD: secret
      SPRING_DATA_REDIS_HOST: redis
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/actuator/health"]
      interval: 30s
      timeout: 3s
      start_period: 60s
      retries: 3

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: secret
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
      interval: 10s
      timeout: 3s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

volumes:
  pgdata:
```

## Framework-Specific Patterns

### Spring Profiles via Environment

Spring Boot binds environment variables to configuration properties using relaxed binding. `SPRING_DATASOURCE_URL` maps to `spring.datasource.url`.

```yaml
environment:
  SPRING_PROFILES_ACTIVE: local
  # Override any application.yml property via env var:
  SPRING_JPA_HIBERNATE_DDL_AUTO: create-drop
  SERVER_PORT: 8080
  MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE: health,info,prometheus
```

### Spring Boot DevTools with Live Reload

```yaml
# compose.dev.yaml (overlay for development)
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    environment:
      SPRING_DEVTOOLS_RESTART_ENABLED: "true"
      SPRING_DEVTOOLS_LIVERELOAD_ENABLED: "true"
    volumes:
      - ./build/classes:/app/classes
      - ./build/resources:/app/resources
    ports:
      - "8080:8080"
      - "35729:35729"  # LiveReload port
```

Run with `docker compose -f compose.yaml -f compose.dev.yaml up`. Mount compiled classes for hot-reload without full image rebuild.

### Testcontainers Auto-Detection

Spring Boot 3.1+ `spring-boot-docker-compose` detects `compose.yaml` and manages its lifecycle automatically during local development. When using Testcontainers in tests, disable Docker Compose auto-start to avoid port conflicts:

```yaml
# application-test.yml
spring:
  docker:
    compose:
      enabled: false
```

### Full Stack with Monitoring

```yaml
services:
  app:
    build: .
    environment:
      SPRING_PROFILES_ACTIVE: local
      MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE: health,info,prometheus
      MANAGEMENT_OTLP_TRACING_ENDPOINT: http://otel-collector:4318/v1/traces
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: secret
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
      interval: 10s
      retries: 5

  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
```

## Scaffolder Patterns

```yaml
patterns:
  compose: "compose.yaml"
  compose_dev: "compose.dev.yaml"
  compose_test: "compose.test.yaml"
```

## Additional Dos

- DO use `depends_on` with `condition: service_healthy` for database dependencies
- DO configure Spring profiles via `SPRING_PROFILES_ACTIVE` environment variable
- DO use compose overlay files (`compose.dev.yaml`) for development-specific configuration
- DO set `start_period` on app healthcheck to accommodate Spring Boot startup time

## Additional Don'ts

- DON'T hardcode database credentials in `application.yml` -- pass them via Compose environment
- DON'T mount source code into production containers -- only use volume mounts in development overlays
- DON'T enable `spring-boot-docker-compose` and manual Compose simultaneously -- choose one
- DON'T expose management ports to the host in production -- keep Actuator on the internal network
