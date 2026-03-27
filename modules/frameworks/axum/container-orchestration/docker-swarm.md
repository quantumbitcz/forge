# Docker Swarm with Axum

> Extends `modules/container-orchestration/docker-swarm.md` with Axum service deployment patterns.
> Generic Docker Swarm conventions (service replicas, overlay networks, rolling updates) are NOT repeated here.

## Integration Setup

```yaml
# docker-stack.yml
version: "3.8"

services:
  app:
    image: registry.example.com/axum-app:latest
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 5s
        order: start-first
        failure_action: rollback
      restart_policy:
        condition: on-failure
        max_attempts: 3
    environment:
      RUST_LOG: info
    secrets:
      - db-url
    networks:
      - backend

secrets:
  db-url:
    external: true

networks:
  backend:
    driver: overlay
```

Rust binaries start in milliseconds. The `delay: 5s` is conservative -- Axum is ready almost instantly.

## Scaffolder Patterns

```yaml
patterns:
  stack: "docker-stack.yml"
```

## Additional Dos

- DO use `start-first` -- Axum starts in milliseconds
- DO use Docker secrets for database URLs
- DO keep `delay` short -- Rust binaries have near-instant startup
- DO use `RUST_LOG` for log level configuration

## Additional Don'ts

- DON'T set `start_period` too long -- Axum starts instantly
- DON'T embed secrets in environment variables
- DON'T set `RUST_LOG=debug` in production
