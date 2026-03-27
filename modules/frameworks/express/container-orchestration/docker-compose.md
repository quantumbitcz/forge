# Docker Compose with Express

> Extends `modules/container-orchestration/docker-compose.md` with Express service composition patterns.
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
      - "3000:3000"
    environment:
      DATABASE_URL: postgresql://app:secret@postgres:5432/app
      REDIS_URL: redis://redis:6379
      NODE_ENV: production
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "node", "-e", "fetch('http://localhost:3000/health').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"]
      interval: 30s
      timeout: 3s
      start_period: 5s
      retries: 3

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: secret
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
      interval: 10s
      retries: 5

  redis:
    image: redis:7-alpine

volumes:
  pgdata:
```

## Framework-Specific Patterns

### Development Overlay with Hot Reload

```yaml
# compose.dev.yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    command: npx tsx watch src/index.ts
    volumes:
      - ./src:/app/src
    environment:
      NODE_ENV: development
    ports:
      - "3000:3000"
      - "9229:9229"  # Node.js debugger
```

### BullMQ Worker Sidecar

```yaml
services:
  worker:
    build: .
    command: node dist/worker.js
    environment:
      REDIS_URL: redis://redis:6379
      DATABASE_URL: postgresql://app:secret@postgres:5432/app
    depends_on:
      - redis
      - postgres
```

## Scaffolder Patterns

```yaml
patterns:
  compose: "compose.yaml"
  compose_dev: "compose.dev.yaml"
```

## Additional Dos

- DO use `depends_on` with `condition: service_healthy` for database dependencies
- DO use compose overlay files for development hot-reload configuration
- DO separate background job workers into distinct services
- DO expose port 9229 in development for Node.js debugger attachment

## Additional Don'ts

- DON'T mount `node_modules/` from host into container -- it causes platform-specific binary issues
- DON'T use `nodemon` in production -- only in development overlays
- DON'T set `NODE_ENV=development` in production compose files
