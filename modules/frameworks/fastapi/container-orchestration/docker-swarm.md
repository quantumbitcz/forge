# Docker Swarm with FastAPI

> Extends `modules/container-orchestration/docker-swarm.md` with FastAPI service deployment patterns.
> Generic Docker Swarm conventions (service replicas, overlay networks, rolling updates) are NOT repeated here.

## Integration Setup

```yaml
# docker-stack.yml
version: "3.8"

services:
  app:
    image: registry.example.com/fastapi-app:latest
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 10s
        order: start-first
        failure_action: rollback
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
    environment:
      DATABASE_URL: postgresql://app:secret@postgres:5432/app
      UVICORN_WORKERS: 4
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
      interval: 30s
      timeout: 5s
      start_period: 10s
      retries: 3
    networks:
      - backend

networks:
  backend:
    driver: overlay
```

## Framework-Specific Patterns

### Uvicorn Workers and Replicas

Set Uvicorn `--workers` per container and Swarm `replicas` for the service. Total concurrency = workers * replicas. For a 2-CPU container limit with 3 replicas: `--workers 4` yields 12 total workers.

```yaml
environment:
  UVICORN_WORKERS: "4"
```

```dockerfile
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "${UVICORN_WORKERS:-4}"]
```

### Secrets for Sensitive Config

```yaml
services:
  app:
    secrets:
      - db-url
      - jwt-secret
    environment:
      DATABASE_URL_FILE: /run/secrets/db-url

secrets:
  db-url:
    external: true
  jwt-secret:
    external: true
```

Read secrets from files in the application:

```python
import os
from pathlib import Path

def get_secret(env_var: str) -> str:
    file_path = os.getenv(f"{env_var}_FILE")
    if file_path:
        return Path(file_path).read_text().strip()
    return os.environ[env_var]
```

### Rolling Update Strategy

```yaml
deploy:
  update_config:
    parallelism: 1
    delay: 10s
    order: start-first
    failure_action: rollback
    monitor: 30s
```

FastAPI starts in under a second, so `delay: 10s` is sufficient. Use `start-first` for zero-downtime deployments.

## Scaffolder Patterns

```yaml
patterns:
  stack: "docker-stack.yml"
```

## Additional Dos

- DO use `start-first` update order -- FastAPI starts fast, enabling zero-downtime deploys
- DO tune `UVICORN_WORKERS` based on container CPU limits
- DO use Docker secrets for database URLs and JWT keys
- DO set `monitor` in `update_config` to detect post-deploy failures

## Additional Don'ts

- DON'T set `start_period` too long -- FastAPI starts in under a second
- DON'T embed secrets in environment variables in the stack file
- DON'T scale Celery beat to more than 1 replica in the same stack
