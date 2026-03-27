# Docker Swarm with Django

> Extends `modules/container-orchestration/docker-swarm.md` with Django service deployment patterns.
> Generic Docker Swarm conventions (service replicas, overlay networks, rolling updates) are NOT repeated here.

## Integration Setup

```yaml
# docker-stack.yml
version: "3.8"

services:
  app:
    image: registry.example.com/django-app:latest
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 15s
        order: start-first
        failure_action: rollback
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
    environment:
      DJANGO_SETTINGS_MODULE: config.settings.production
      GUNICORN_WORKERS: 4
    secrets:
      - db-url
      - django-secret-key
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health/')"]
      interval: 30s
      timeout: 5s
      start_period: 15s
      retries: 3
    networks:
      - backend

secrets:
  db-url:
    external: true
  django-secret-key:
    external: true

networks:
  backend:
    driver: overlay
```

## Framework-Specific Patterns

### Secret File Reading

```python
# config/settings/production.py
import os
from pathlib import Path

def read_secret(name: str, default: str = "") -> str:
    secret_path = Path(f"/run/secrets/{name}")
    if secret_path.exists():
        return secret_path.read_text().strip()
    return os.getenv(name.upper().replace("-", "_"), default)

SECRET_KEY = read_secret("django-secret-key")
DATABASES = {
    "default": dj_database_url.parse(read_secret("db-url"))
}
```

### Rolling Update Strategy

```yaml
deploy:
  update_config:
    parallelism: 1
    delay: 15s
    order: start-first
    failure_action: rollback
    monitor: 30s
```

Gunicorn startup is fast (1-2s), so `delay: 15s` provides ample time for health checks to pass.

### Static Files with Whitenoise

Static files are baked into the image via `collectstatic` at build time. No volume mount needed. Whitenoise serves them directly from the application process.

## Scaffolder Patterns

```yaml
patterns:
  stack: "docker-stack.yml"
```

## Additional Dos

- DO use `start-first` update order for zero-downtime deployments
- DO use Docker secrets for `SECRET_KEY` and `DATABASE_URL`
- DO bake static files into the image with `collectstatic` at build time
- DO set `monitor` in `update_config` to detect post-deploy failures

## Additional Don'ts

- DON'T embed secrets in environment variables in the stack file
- DON'T use Django's `runserver` in Swarm -- use Gunicorn
- DON'T scale Celery beat to more than 1 replica
