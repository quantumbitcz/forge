# Docker Compose with Next.js

> Extends `modules/container-orchestration/docker-compose.md` with Next.js service composition patterns.
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
      NEXTAUTH_URL: http://localhost:3000
    volumes:
      - nextcache:/app/.next/cache
    depends_on:
      postgres:
        condition: service_healthy

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

volumes:
  pgdata:
  nextcache:
```

## Framework-Specific Patterns

### Development Overlay

```yaml
# compose.dev.yaml
services:
  app:
    command: npm run dev
    volumes:
      - .:/app
      - /app/node_modules
      - /app/.next
    environment:
      NODE_ENV: development
    ports:
      - "3000:3000"
```

Exclude `node_modules` and `.next` from the host mount to avoid overwriting container-installed dependencies.

### ISR Cache Persistence

```yaml
volumes:
  nextcache:
    driver: local
```

Mount `.next/cache` as a named volume so ISR-regenerated pages persist across container restarts.

## Scaffolder Patterns

```yaml
patterns:
  compose: "compose.yaml"
  compose_dev: "compose.dev.yaml"
```

## Additional Dos

- DO mount `.next/cache` as a volume for ISR persistence
- DO exclude `node_modules` and `.next` from development bind mounts
- DO use compose overlays for development hot-reload
- DO set `NEXTAUTH_URL` for authentication in development

## Additional Don'ts

- DON'T mount source code in production containers
- DON'T include `NEXT_PUBLIC_*` secrets in compose files -- they're embedded at build time
- DON'T use `npm run dev` in production compose configurations
