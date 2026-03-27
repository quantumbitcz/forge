# Docker Swarm with SvelteKit

> Extends `modules/container-orchestration/docker-swarm.md` with SvelteKit adapter-node deployment patterns.
> Generic Docker Swarm conventions (service replicas, overlay networks, rolling updates) are NOT repeated here.

## Integration Setup

```yaml
# docker-stack.yml
version: "3.8"

services:
  app:
    image: registry.example.com/sveltekit-app:latest
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 10s
        order: start-first
        failure_action: rollback
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
    environment:
      NODE_ENV: production
      APP_API_URL: http://api:8080
      APP_PUBLIC_SITE_URL: https://example.com
      PORT: 3000
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/"]
      interval: 30s
      timeout: 5s
      start_period: 10s
      retries: 3
    networks:
      - frontend
      - backend

networks:
  frontend:
    driver: overlay
  backend:
    driver: overlay
```

## Framework-Specific Patterns

### Fast Startup for Rolling Updates

SvelteKit with `adapter-node` starts in under 2 seconds (compared to 30-90s for JVM apps). Set `delay` and `start_period` accordingly -- shorter values enable faster rolling updates.

```yaml
deploy:
  update_config:
    delay: 10s        # SvelteKit starts fast, no need for 30s+
    order: start-first
    monitor: 15s
```

### Secrets via Docker Secrets

```yaml
services:
  app:
    secrets:
      - db-connection-string
      - api-key
    environment:
      DATABASE_URL_FILE: /run/secrets/db-connection-string
      APP_API_KEY_FILE: /run/secrets/api-key

secrets:
  db-connection-string:
    external: true
  api-key:
    external: true
```

Read secrets in SvelteKit hooks or load functions:

```typescript
// src/hooks.server.ts
import { readFileSync } from "fs";
const dbUrl = readFileSync("/run/secrets/db-connection-string", "utf-8").trim();
```

## Scaffolder Patterns

```yaml
patterns:
  stack: "docker-stack.yml"
```

## Additional Dos

- DO use `start-first` update order for zero-downtime deployments
- DO leverage SvelteKit's fast startup for shorter `delay` and `start_period` values
- DO use Docker secrets for sensitive configuration
- DO place the app on both frontend and backend overlay networks

## Additional Don'ts

- DON'T set overly long `start_period` -- SvelteKit starts in under 2 seconds
- DON'T embed secrets in environment variables -- use Docker secrets mounted to `/run/secrets/`
- DON'T set `max_attempts` too high on restart policy
