# Docker Compose with Django

> Extends `modules/container-orchestration/docker-compose.md` with Django service composition patterns.
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
      DJANGO_SETTINGS_MODULE: config.settings.local
      DATABASE_URL: postgresql://app:secret@postgres:5432/app
      REDIS_URL: redis://redis:6379/0
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started

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
    command: python manage.py runserver 0.0.0.0:8000
    volumes:
      - .:/app
    environment:
      DJANGO_SETTINGS_MODULE: config.settings.local
```

Run with `docker compose -f compose.yaml -f compose.dev.yaml up`. The dev server auto-reloads on code changes.

### Celery Worker and Beat

```yaml
services:
  worker:
    build: .
    command: celery -A config worker --loglevel=info
    environment:
      DJANGO_SETTINGS_MODULE: config.settings.local
      DATABASE_URL: postgresql://app:secret@postgres:5432/app
      CELERY_BROKER_URL: redis://redis:6379/0
    depends_on:
      - redis
      - postgres

  beat:
    build: .
    command: celery -A config beat --loglevel=info --scheduler django_celery_beat.schedulers:DatabaseScheduler
    environment:
      DJANGO_SETTINGS_MODULE: config.settings.local
      CELERY_BROKER_URL: redis://redis:6379/0
    depends_on:
      - redis
      - postgres
```

### Migration Service

```yaml
services:
  migrate:
    build: .
    command: python manage.py migrate --noinput
    environment:
      DJANGO_SETTINGS_MODULE: config.settings.local
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

- DO use `depends_on` with `condition: service_healthy` for database dependencies
- DO use compose overlay files for development-specific configuration
- DO separate Celery workers and beat scheduler into distinct services
- DO set `DJANGO_SETTINGS_MODULE` explicitly per service

## Additional Don'ts

- DON'T mount source code in production containers -- only in development overlays
- DON'T use `runserver` in production -- use Gunicorn
- DON'T run Celery beat with `DatabaseScheduler` on multiple replicas
- DON'T hardcode `SECRET_KEY` in compose files
