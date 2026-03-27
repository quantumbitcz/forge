# Docker Compose with Gin

> Extends `modules/container-orchestration/docker-compose.md` with Gin service composition patterns.
> Generic Docker Compose conventions (service definitions, networking, volumes) are NOT repeated here.

## Integration Setup

```yaml
services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      GIN_MODE: release
      DATABASE_URL: postgresql://app:secret@postgres:5432/app
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

### Development Overlay with Air

```yaml
# compose.dev.yaml
services:
  app:
    build:
      dockerfile: Dockerfile.dev
    command: air
    volumes:
      - .:/app
    environment:
      GIN_MODE: debug
```

[Air](https://github.com/cosmtrek/air) provides live-reload for Go development.

## Scaffolder Patterns

```yaml
patterns:
  compose: "compose.yaml"
  compose_dev: "compose.dev.yaml"
```

## Additional Dos

- DO set `GIN_MODE=release` in production
- DO use compose overlays for development with live-reload
- DO use `depends_on` with health checks for databases

## Additional Don'ts

- DON'T set `GIN_MODE=debug` in production
- DON'T mount source code in production containers
