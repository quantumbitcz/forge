# Docker Swarm with Go stdlib

> Extends `modules/container-orchestration/docker-swarm.md` with Go stdlib service deployment patterns.
> Generic Docker Swarm conventions (service replicas, overlay networks, rolling updates) are NOT repeated here.

## Integration Setup

```yaml
version: "3.8"

services:
  app:
    image: registry.example.com/go-app:latest
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 5s
        order: start-first
        failure_action: rollback
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

## Scaffolder Patterns

```yaml
patterns:
  stack: "docker-stack.yml"
```

## Additional Dos

- DO use `start-first` -- Go starts instantly
- DO use Docker secrets for credentials
- DO keep delay short

## Additional Don'ts

- DON'T embed secrets in environment variables
- DON'T set delay too long
