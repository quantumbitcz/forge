# Docker Swarm with Spring

> Extends `modules/container-orchestration/docker-swarm.md` with Spring Boot service deployment patterns.
> Generic Docker Swarm conventions (service replicas, overlay networks, rolling updates) are NOT repeated here.

## Integration Setup

```yaml
# docker-stack.yml
version: "3.8"

services:
  app:
    image: registry.example.com/spring-app:latest
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 30s
        order: start-first
        failure_action: rollback
      rollback_config:
        parallelism: 1
      restart_policy:
        condition: on-failure
        delay: 10s
        max_attempts: 3
    environment:
      SPRING_PROFILES_ACTIVE: production
      SPRING_CONFIG_IMPORT: configserver:http://config-server:8888
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/actuator/health/liveness"]
      interval: 30s
      timeout: 5s
      start_period: 90s
      retries: 3
    networks:
      - backend

networks:
  backend:
    driver: overlay
```

## Framework-Specific Patterns

### Config Injection via Docker Configs

```yaml
services:
  app:
    image: registry.example.com/spring-app:latest
    configs:
      - source: app-config
        target: /app/config/application-production.yml
    environment:
      SPRING_PROFILES_ACTIVE: production
      SPRING_CONFIG_ADDITIONAL_LOCATION: /app/config/

configs:
  app-config:
    file: ./config/application-production.yml
```

Docker configs are mounted as read-only files. Spring Boot picks them up via `SPRING_CONFIG_ADDITIONAL_LOCATION`. Rotate configs by creating a new version and updating the service.

### Secrets for Sensitive Properties

```yaml
services:
  app:
    image: registry.example.com/spring-app:latest
    secrets:
      - db-password
      - jwt-secret
    environment:
      SPRING_DATASOURCE_PASSWORD_FILE: /run/secrets/db-password
      APP_JWT_SECRET_FILE: /run/secrets/jwt-secret

secrets:
  db-password:
    external: true
  jwt-secret:
    external: true
```

Use Spring Boot's `_FILE` suffix convention (via a custom `EnvironmentPostProcessor`) or read secrets in application startup. Docker secrets mount to `/run/secrets/` as tmpfs.

### Health Check Endpoints

```yaml
# application.yml
management:
  endpoint:
    health:
      probes:
        enabled: true
      show-details: when_authorized
  health:
    livenessState:
      enabled: true
    readinessState:
      enabled: true
```

Swarm uses the `healthcheck` directive for container health. Map:
- Liveness: `/actuator/health/liveness` -- is the JVM alive?
- Readiness: use `start-first` deployment order so Swarm routes traffic only after the new task is healthy

### Rolling Update Strategy

```yaml
deploy:
  update_config:
    parallelism: 1          # update one task at a time
    delay: 30s              # wait between updates for Spring Boot startup
    order: start-first      # start new before stopping old (zero-downtime)
    failure_action: rollback
    monitor: 60s            # health check monitoring window after update
```

`start-first` with a `delay` matching Spring Boot's startup time ensures the new instance is healthy before the old one stops.

### Spring Cloud Config Integration

```yaml
services:
  config-server:
    image: registry.example.com/config-server:latest
    deploy:
      replicas: 2
    environment:
      SPRING_CLOUD_CONFIG_SERVER_GIT_URI: https://github.com/org/config-repo
    networks:
      - backend

  app:
    image: registry.example.com/spring-app:latest
    environment:
      SPRING_CONFIG_IMPORT: configserver:http://config-server:8888
    depends_on:
      - config-server
    networks:
      - backend
```

## Scaffolder Patterns

```yaml
patterns:
  stack: "docker-stack.yml"
  config_dir: "config/"
```

## Additional Dos

- DO use `start-first` update order for zero-downtime Spring Boot deployments
- DO set `start_period` on healthcheck to exceed Spring Boot's typical startup time
- DO use Docker configs for `application-{profile}.yml` files and secrets for credentials
- DO set `monitor` in `update_config` to catch post-deploy failures

## Additional Don'ts

- DON'T use `stop-first` update order -- causes downtime during Spring Boot's slow startup
- DON'T embed secrets in Docker configs -- use Docker secrets mounted to `/run/secrets/`
- DON'T set `max_attempts` too high on restart policy -- let the orchestrator escalate failures
