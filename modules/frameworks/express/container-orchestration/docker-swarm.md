# Docker Swarm with Express

> Extends `modules/container-orchestration/docker-swarm.md` with Express service deployment patterns.
> Generic Docker Swarm conventions (service replicas, overlay networks, rolling updates) are NOT repeated here.

## Integration Setup

```yaml
# docker-stack.yml
version: "3.8"

services:
  app:
    image: registry.example.com/express-app:latest
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
    secrets:
      - db-url
    healthcheck:
      test: ["CMD", "node", "-e", "fetch('http://localhost:3000/health').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"]
      interval: 30s
      timeout: 5s
      start_period: 5s
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

### PM2 Cluster Mode in Swarm

When using PM2 cluster mode, set `instances` to match the container CPU limit rather than `max`. Swarm replicas * PM2 instances = total concurrency.

```javascript
// ecosystem.config.js
module.exports = {
  apps: [{
    name: "express-app",
    script: "dist/index.js",
    instances: parseInt(process.env.PM2_INSTANCES || "2"),
    exec_mode: "cluster"
  }]
};
```

### Secrets Reading

```typescript
import { readFileSync, existsSync } from "fs";

function getSecret(name: string): string {
  const path = `/run/secrets/${name}`;
  if (existsSync(path)) {
    return readFileSync(path, "utf-8").trim();
  }
  return process.env[name.toUpperCase().replace(/-/g, "_")] ?? "";
}
```

### Rolling Update Strategy

```yaml
deploy:
  update_config:
    parallelism: 1
    delay: 10s
    order: start-first
    failure_action: rollback
    monitor: 15s
```

Node.js starts fast (sub-second), so `delay: 10s` is conservative. Use `start-first` for zero-downtime.

## Scaffolder Patterns

```yaml
patterns:
  stack: "docker-stack.yml"
```

## Additional Dos

- DO use `start-first` update order -- Node.js starts fast, enabling zero-downtime deploys
- DO use Docker secrets for database URLs and API keys
- DO handle `SIGTERM` for graceful shutdown in Express
- DO tune PM2 instances to match container CPU limits

## Additional Don'ts

- DON'T set `PM2_INSTANCES=max` in containers -- it uses host CPUs, not container limits
- DON'T embed secrets in environment variables in the stack file
- DON'T use `nodemon` or `tsx watch` in production stacks
