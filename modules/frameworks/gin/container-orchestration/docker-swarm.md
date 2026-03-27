# Docker Swarm with Gin

> Extends `modules/container-orchestration/docker-swarm.md` with Gin service deployment patterns.
> Generic Docker Swarm conventions (service replicas, overlay networks, rolling updates) are NOT repeated here.

## Integration Setup

```yaml
version: "3.8"

services:
  app:
    image: registry.example.com/gin-app:latest
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 5s
        order: start-first
        failure_action: rollback
    environment:
      GIN_MODE: release
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

Go binaries start in milliseconds. Minimal delay needed.

## Scaffolder Patterns

```yaml
patterns:
  stack: "docker-stack.yml"
```

## Additional Dos

- DO use `start-first` -- Go binaries start instantly
- DO set `GIN_MODE=release` in production
- DO use Docker secrets for credentials

## Additional Don'ts

- DON'T set delay too long -- Go starts in milliseconds
- DON'T embed secrets in environment variables
