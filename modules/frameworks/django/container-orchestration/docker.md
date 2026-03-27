# Docker with Django

> Extends `modules/container-orchestration/docker.md` with Django containerization patterns.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

### Multi-Stage Dockerfile

```dockerfile
# Stage 1: Build
FROM python:3.12-slim AS builder
WORKDIR /app

RUN pip install uv

COPY pyproject.toml uv.lock ./
RUN uv sync --no-dev --frozen

# Stage 2: Runtime
FROM python:3.12-slim
WORKDIR /app

RUN addgroup --system django && adduser --system --group django

COPY --from=builder /app/.venv /app/.venv
COPY . .

ENV PATH="/app/.venv/bin:$PATH"
ENV DJANGO_SETTINGS_MODULE=config.settings.production

RUN python manage.py collectstatic --noinput

USER django:django

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health/')" || exit 1

CMD ["gunicorn", "config.wsgi:application", \
     "--bind", "0.0.0.0:8000", \
     "--workers", "4", \
     "--worker-class", "gthread", \
     "--threads", "2"]
```

`collectstatic` runs at build time so static files are baked into the image. No need for a volume mount or nginx sidecar if using whitenoise.

## Framework-Specific Patterns

### Gunicorn Production Configuration

```dockerfile
CMD ["gunicorn", "config.wsgi:application", \
     "--bind", "0.0.0.0:8000", \
     "--workers", "4", \
     "--worker-class", "gthread", \
     "--threads", "2", \
     "--max-requests", "1000", \
     "--max-requests-jitter", "50", \
     "--timeout", "30", \
     "--access-logfile", "-"]
```

Set `--workers` to `2 * CPU + 1`. Use `--max-requests` to recycle workers and prevent memory leaks. `gthread` worker class handles mixed I/O-bound workloads.

### Whitenoise for Static Files

```python
# config/settings/production.py
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    # ...
]
STATICFILES_STORAGE = "whitenoise.storage.CompressedManifestStaticFilesStorage"
```

Whitenoise serves static files directly from Django without nginx. Compressed and fingerprinted at `collectstatic` time.

### Django Settings via Environment

```dockerfile
ENV DJANGO_SETTINGS_MODULE=config.settings.production
ENV DJANGO_ALLOWED_HOSTS=*
ENV DJANGO_SECRET_KEY=changeme
```

Override all sensitive settings via environment variables. Never hardcode `SECRET_KEY` in the image.

### Migration Entrypoint

```bash
#!/usr/bin/env bash
set -e
python manage.py migrate --noinput
exec gunicorn config.wsgi:application --bind 0.0.0.0:8000 --workers 4
```

For simple deployments, run migrations in the entrypoint. For orchestrated environments, prefer a separate init container.

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
  entrypoint: "entrypoint.sh"
```

## Additional Dos

- DO run `collectstatic --noinput` at build time to bake static files into the image
- DO use whitenoise for static file serving -- eliminates the nginx dependency
- DO set `--max-requests` on Gunicorn to recycle workers and prevent memory leaks
- DO override `DJANGO_SETTINGS_MODULE` via environment variable, not Dockerfile default

## Additional Don'ts

- DON'T hardcode `SECRET_KEY` in the Dockerfile -- always inject via environment
- DON'T use Django's built-in development server (`runserver`) in production
- DON'T run as root -- create a `django` user and switch before CMD
- DON'T copy `tests/`, `.git/`, or `node_modules/` into the production image
