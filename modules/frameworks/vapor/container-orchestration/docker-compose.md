# Docker Compose with Vapor

> Extends `modules/container-orchestration/docker-compose.md` with Vapor service composition patterns.
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
      VAPOR_ENV: production
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

### Development Overlay

```yaml
# compose.dev.yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    command: swift run App serve --env development --hostname 0.0.0.0 --port 8080
    volumes:
      - .:/app
    environment:
      VAPOR_ENV: development
```

### Fluent Migration Service

```yaml
services:
  migrate:
    build: .
    command: ./App migrate --yes
    environment:
      DATABASE_URL: postgresql://app:secret@postgres:5432/app
    depends_on:
      postgres:
        condition: service_healthy
    profiles:
      - migrate
```

## Scaffolder Patterns

```yaml
patterns:
  compose: "compose.yaml"
  compose_dev: "compose.dev.yaml"
```

## Additional Dos

- DO use `depends_on` with health checks for database dependencies
- DO use profiles for one-off migration tasks
- DO set `VAPOR_ENV` per service

## Additional Don'ts

- DON'T mount source code in production
- DON'T use development environment in production
