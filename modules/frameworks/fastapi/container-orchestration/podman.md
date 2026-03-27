# Podman with FastAPI

> Extends `modules/container-orchestration/podman.md` with FastAPI containerization patterns.
> Generic Podman conventions (rootless containers, pod definitions, systemd integration) are NOT repeated here.

## Integration Setup

```bash
podman build -t fastapi-app:latest .
podman run -d --name fastapi-app -p 8000:8000 \
  -e APP_ENV=production \
  fastapi-app:latest
```

## Framework-Specific Patterns

### Pod with Database

```bash
podman pod create --name fastapi-pod -p 8000:8000 -p 5432:5432

podman run -d --pod fastapi-pod --name postgres \
  -e POSTGRES_DB=app -e POSTGRES_USER=app -e POSTGRES_PASSWORD=secret \
  postgres:16-alpine

podman run -d --pod fastapi-pod --name fastapi-app \
  -e DATABASE_URL=postgresql://app:secret@localhost:5432/app \
  -e APP_ENV=production \
  fastapi-app:latest
```

Podman pods share a network namespace. FastAPI connects to PostgreSQL via `localhost`.

### Quadlet Integration

```ini
[Container]
Image=registry.example.com/fastapi-app:latest
PublishPort=8000:8000
Environment=APP_ENV=production
Secret=db-url,type=env,target=DATABASE_URL

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### Buildah Multi-Stage Build

```bash
buildah from --name builder python:3.12-slim
buildah run builder -- pip install --no-cache-dir poetry
buildah copy builder pyproject.toml poetry.lock /app/
buildah run builder -- sh -c 'cd /app && poetry export -f requirements.txt -o requirements.txt --without-hashes'

buildah from --name runtime python:3.12-slim
buildah copy --from builder runtime /app/requirements.txt /app/
buildah run runtime -- pip install --no-cache-dir -r /app/requirements.txt
buildah copy runtime . /app/
buildah config --cmd '["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]' --workingdir /app runtime
buildah commit runtime fastapi-app:latest
```

### Alembic Migration

```bash
podman run --rm --pod fastapi-pod \
  -e DATABASE_URL=postgresql://app:secret@localhost:5432/app \
  fastapi-app:latest alembic upgrade head
```

### Uvicorn Workers

```bash
podman run -d --pod fastapi-pod --name fastapi-app \
  -e DATABASE_URL=postgresql://app:secret@localhost:5432/app \
  -e APP_ENV=production \
  fastapi-app:latest \
  uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
```

Scale workers based on available CPUs. Use `2 * CPU_CORES + 1` as a baseline.

## Scaffolder Patterns

```yaml
patterns:
  quadlet: "deploy/fastapi-app.container"
```

## Additional Dos

- DO use Podman pods for FastAPI + database development environments
- DO use Quadlet for systemd-managed production deployments
- DO use `--workers` with Uvicorn for multi-process production deployment
- DO use Poetry export for deterministic `requirements.txt` generation

## Additional Don'ts

- DON'T use `--reload` in production
- DON'T skip `--pod` when running with a database
- DON'T install Poetry in the production image -- export requirements in the build stage
- DON'T use `--privileged`
