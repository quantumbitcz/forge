# Docker Compose with FastAPI

> Extends `modules/container-orchestration/docker-compose.md` with FastAPI service composition patterns.
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
      - "8000:8000"
    environment:
      DATABASE_URL: postgresql://app:secret@postgres:5432/app
      REDIS_URL: redis://redis:6379/0
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
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
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
      interval: 10s
      timeout: 3s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

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
    command: uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
    volumes:
      - ./app:/app/app
      - ./alembic:/app/alembic
    ports:
      - "8000:8000"
```

Run with `docker compose -f compose.yaml -f compose.dev.yaml up`. Mount source code for hot-reload during development.

### Celery Worker Sidecar

```yaml
services:
  app:
    build: .
    environment:
      CELERY_BROKER_URL: redis://redis:6379/0

  worker:
    build: .
    command: celery -A app.celery worker --loglevel=info
    environment:
      CELERY_BROKER_URL: redis://redis:6379/0
      DATABASE_URL: postgresql://app:secret@postgres:5432/app
    depends_on:
      - redis
      - postgres

  beat:
    build: .
    command: celery -A app.celery beat --loglevel=info
    environment:
      CELERY_BROKER_URL: redis://redis:6379/0
    depends_on:
      - redis
```

### Alembic Migration Service

```yaml
services:
  migrate:
    build: .
    command: alembic upgrade head
    environment:
      DATABASE_URL: postgresql://app:secret@postgres:5432/app
    depends_on:
      postgres:
        condition: service_healthy
    profiles:
      - migrate
```

Run with `docker compose --profile migrate run migrate`.

## Scaffolder Patterns

```yaml
patterns:
  compose: "compose.yaml"
  compose_dev: "compose.dev.yaml"
```

## Additional Dos

- DO use `depends_on` with `condition: service_healthy` for database dependencies
- DO use compose overlay files for development-specific hot-reload configuration
- DO separate Celery workers and beat scheduler into distinct services
- DO use profiles for one-off tasks like migrations

## Additional Don'ts

- DON'T mount source code in production containers -- only in development overlays
- DON'T hardcode database credentials in application code -- pass via Compose environment
- DON'T run Celery beat with multiple replicas -- it causes duplicate scheduled tasks
- DON'T use `--reload` in production Compose configurations
