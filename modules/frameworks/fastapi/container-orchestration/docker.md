# Docker with FastAPI

> Extends `modules/container-orchestration/docker.md` with FastAPI containerization patterns.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

### Multi-Stage Dockerfile

```dockerfile
# Stage 1: Build dependencies
FROM python:3.12-slim AS builder
WORKDIR /app

RUN pip install uv

COPY pyproject.toml uv.lock ./
RUN uv sync --no-dev --frozen

# Stage 2: Runtime
FROM python:3.12-slim
WORKDIR /app

RUN addgroup --system app && adduser --system --group app

COPY --from=builder /app/.venv /app/.venv
COPY app/ ./app/
COPY alembic/ ./alembic/
COPY alembic.ini ./

ENV PATH="/app/.venv/bin:$PATH"

USER app:app

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

The build stage installs dependencies into a virtual environment; the runtime stage copies only the venv and application code. No build tools in the final image.

## Framework-Specific Patterns

### Uvicorn Production Configuration

```dockerfile
CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--workers", "4", \
     "--loop", "uvloop", \
     "--http", "httptools", \
     "--no-access-log"]
```

Set `--workers` to `2 * CPU + 1` for the container's CPU limit. Use `uvloop` and `httptools` for maximum throughput. Disable access logs in production when using a reverse proxy that logs requests.

### Health Check Endpoint

```python
# app/main.py
@app.get("/health")
async def health():
    return {"status": "ok"}
```

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1
```

FastAPI starts fast (sub-second), so `start-period` can be short. Use Python's `urllib` for the health check since `curl`/`wget` may not be in slim images.

### Alembic Migrations in Entrypoint

```dockerfile
COPY entrypoint.sh ./
RUN chmod +x entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]
```

```bash
#!/usr/bin/env bash
set -e
alembic upgrade head
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Run migrations as part of the entrypoint for simple deployments. For orchestrated environments, prefer a separate init container or job.

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
  entrypoint: "entrypoint.sh"
```

## Additional Dos

- DO use multi-stage builds to keep the runtime image free of build tools
- DO install dependencies with `uv sync --no-dev --frozen` for reproducible production installs
- DO set Uvicorn `--workers` based on the container's CPU limit
- DO use `python -c "import urllib.request; ..."` for health checks in slim images

## Additional Don'ts

- DON'T use `uvicorn --reload` in production -- it watches the filesystem and increases CPU usage
- DON'T install `gcc`/`build-essential` in the runtime stage -- compile C extensions in the builder
- DON'T run as root -- create an `app` user and switch before ENTRYPOINT
- DON'T copy `tests/` or `.venv/` into the production image
