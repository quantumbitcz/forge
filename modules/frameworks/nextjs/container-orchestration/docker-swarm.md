# Docker Swarm with Next.js

> Extends `modules/container-orchestration/docker-swarm.md` with Next.js service deployment patterns.
> Generic Docker Swarm conventions (service replicas, overlay networks, rolling updates) are NOT repeated here.

## Integration Setup

```yaml
# docker-stack.yml
version: "3.8"

services:
  app:
    image: registry.example.com/nextjs-app:latest
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
      - nextauth-secret
    volumes:
      - nextcache:/app/.next/cache
    healthcheck:
      test: ["CMD", "node", "-e", "fetch('http://localhost:3000/api/health').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"]
      interval: 30s
      timeout: 5s
      start_period: 10s
      retries: 3
    networks:
      - frontend

volumes:
  nextcache:

secrets:
  db-url:
    external: true
  nextauth-secret:
    external: true

networks:
  frontend:
    driver: overlay
```

## Framework-Specific Patterns

### ISR with Shared Volume

When using ISR with multiple replicas, mount a shared volume so all replicas access the same regenerated pages. Alternatively, use a CDN or Redis-based ISR cache.

### Environment Variables at Runtime

Next.js `NEXT_PUBLIC_*` variables are embedded at build time. Runtime-only secrets (database URLs, auth secrets) are passed via Docker secrets or environment variables.

## Scaffolder Patterns

```yaml
patterns:
  stack: "docker-stack.yml"
```

## Additional Dos

- DO use `start-first` for zero-downtime deployments
- DO mount `.next/cache` as a volume for ISR persistence
- DO use Docker secrets for runtime credentials
- DO set `HOSTNAME=0.0.0.0` for container networking

## Additional Don'ts

- DON'T embed runtime secrets as `NEXT_PUBLIC_*` -- they're baked into the client bundle
- DON'T skip the ISR cache volume -- regenerated pages are lost on container restart
- DON'T set `start_period` too long -- Next.js starts fast
