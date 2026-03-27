# Docker Swarm with NestJS

> Extends `modules/container-orchestration/docker-swarm.md` with NestJS service deployment patterns.
> Generic Docker Swarm conventions (service replicas, overlay networks, rolling updates) are NOT repeated here.

## Integration Setup

```yaml
# docker-stack.yml
version: "3.8"

services:
  app:
    image: registry.example.com/nestjs-app:latest
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 10s
        order: start-first
        failure_action: rollback
      restart_policy:
        condition: on-failure
        max_attempts: 3
    environment:
      NODE_ENV: production
    secrets:
      - db-url
    healthcheck:
      test: ["CMD", "node", "-e", "fetch('http://localhost:3000/health').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"]
      interval: 30s
      timeout: 5s
      start_period: 10s
      retries: 3
    networks:
      - backend

secrets:
  db-url:
    external: true

networks:
  backend:
    driver: overlay
```

## Framework-Specific Patterns

### Shutdown Hooks for Swarm

NestJS `enableShutdownHooks()` handles Swarm's `SIGTERM` during rolling updates. All `OnModuleDestroy` handlers run -- closing DB connections, flushing queues, and draining HTTP requests.

### Microservice Transport in Swarm

```yaml
services:
  api-gateway:
    image: registry.example.com/api-gateway:latest
    deploy:
      replicas: 2
    networks:
      - frontend
      - backend

  order-service:
    image: registry.example.com/order-service:latest
    deploy:
      replicas: 3
    networks:
      - backend
```

Swarm DNS resolves service names within overlay networks. NestJS `ClientProxy` connects to `order-service:3001` using the service name.

## Scaffolder Patterns

```yaml
patterns:
  stack: "docker-stack.yml"
```

## Additional Dos

- DO call `enableShutdownHooks()` for graceful container shutdown
- DO use overlay networks for microservice transport
- DO use Docker secrets for database URLs
- DO use `start-first` update order for zero-downtime deploys

## Additional Don'ts

- DON'T embed secrets in environment variables in the stack file
- DON'T set `start_period` too long -- NestJS starts fast
- DON'T expose microservice transport ports outside the overlay network
