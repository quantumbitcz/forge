# Docker Compose with ASP.NET

> Extends `modules/container-orchestration/docker-compose.md` with ASP.NET Core service composition patterns.
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
      - "8080:8080"
    environment:
      ASPNETCORE_ENVIRONMENT: Development
      ConnectionStrings__DefaultConnection: Host=postgres;Database=app;Username=app;Password=secret
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

### Connection Strings via Environment

ASP.NET Core binds `ConnectionStrings__DefaultConnection` to `ConnectionStrings:DefaultConnection` in configuration. Double underscores map to section delimiters.

### Development Overlay

```yaml
# compose.dev.yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    environment:
      ASPNETCORE_ENVIRONMENT: Development
      DOTNET_USE_POLLING_FILE_WATCHER: "true"
    volumes:
      - .:/src
    ports:
      - "8080:8080"
```

## Scaffolder Patterns

```yaml
patterns:
  compose: "compose.yaml"
  compose_dev: "compose.dev.yaml"
```

## Additional Dos

- DO use `depends_on` with `condition: service_healthy` for database dependencies
- DO use double underscore notation for nested configuration keys
- DO use compose overlays for development-specific configuration
- DO set `ASPNETCORE_ENVIRONMENT` per service

## Additional Don'ts

- DON'T hardcode connection strings in appsettings.json -- inject via environment
- DON'T use `ASPNETCORE_ENVIRONMENT=Development` in production
- DON'T mount source code in production containers
