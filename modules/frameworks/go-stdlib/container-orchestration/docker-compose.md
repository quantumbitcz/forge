# Docker Compose with Go stdlib

> Extends `modules/container-orchestration/docker-compose.md` with Go stdlib service composition patterns.
> Generic Docker Compose conventions (service definitions, networking, volumes) are NOT repeated here.

## Integration Setup

```yaml
services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      DATABASE_URL: postgresql://app:secret@postgres:5432/app
      LOG_LEVEL: info
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
```

## Framework-Specific Patterns

### Development with Air

```yaml
# compose.dev.yaml
services:
  app:
    build:
      dockerfile: Dockerfile.dev
    command: air
    volumes:
      - .:/app
```

## Scaffolder Patterns

```yaml
patterns:
  compose: "compose.yaml"
  compose_dev: "compose.dev.yaml"
```

## Additional Dos

- DO use `depends_on` with health checks
- DO use compose overlays for development

## Additional Don'ts

- DON'T mount source code in production
- DON'T set `LOG_LEVEL=debug` in production
