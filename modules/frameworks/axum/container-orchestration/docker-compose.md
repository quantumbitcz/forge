# Docker Compose with Axum

> Extends `modules/container-orchestration/docker-compose.md` with Axum service composition patterns.
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
      RUST_LOG: info
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

### Development Overlay with cargo-watch

```yaml
# compose.dev.yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    command: cargo watch -x run
    volumes:
      - .:/app
      - cargo-cache:/app/target
    environment:
      RUST_LOG: debug
```

Mount `target/` as a named volume to avoid rebuilding all dependencies on every source change.

## Scaffolder Patterns

```yaml
patterns:
  compose: "compose.yaml"
  compose_dev: "compose.dev.yaml"
```

## Additional Dos

- DO use `depends_on` with health checks for database dependencies
- DO use `RUST_LOG` environment variable for log level configuration
- DO mount `target/` as a named volume in development for build caching
- DO use compose overlays for development configuration

## Additional Don'ts

- DON'T mount source code in production containers
- DON'T use `cargo run` in production -- use the compiled release binary
- DON'T set `RUST_LOG=debug` in production
