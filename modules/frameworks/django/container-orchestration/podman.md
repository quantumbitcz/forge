# Podman with Django

> Extends `modules/container-orchestration/podman.md` with Django containerization patterns.
> Generic Podman conventions (rootless containers, pod definitions, systemd integration) are NOT repeated here.

## Integration Setup

```bash
podman build -t django-app:latest .
podman run -d --name django-app -p 8000:8000 \
  -e DJANGO_SETTINGS_MODULE=config.settings.production \
  django-app:latest
```

## Framework-Specific Patterns

### Pod with Database

```bash
podman pod create --name django-pod -p 8000:8000 -p 5432:5432

podman run -d --pod django-pod --name postgres \
  -e POSTGRES_DB=app -e POSTGRES_USER=app -e POSTGRES_PASSWORD=secret \
  postgres:16-alpine

podman run -d --pod django-pod --name django-app \
  -e DATABASE_URL=postgresql://app:secret@localhost:5432/app \
  -e DJANGO_SETTINGS_MODULE=config.settings.production \
  django-app:latest \
  gunicorn config.wsgi:application --bind 0.0.0.0:8000 --workers 4
```

Podman pods share a network namespace. Django connects to PostgreSQL via `localhost`.

### Quadlet Integration

```ini
[Container]
Image=registry.example.com/django-app:latest
PublishPort=8000:8000
Environment=DJANGO_SETTINGS_MODULE=config.settings.production
Secret=db-url,type=env,target=DATABASE_URL
Secret=secret-key,type=env,target=DJANGO_SECRET_KEY

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
buildah config --cmd '["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "4"]' --workingdir /app runtime
buildah commit runtime django-app:latest
```

### Django Migration

```bash
podman run --rm --pod django-pod \
  -e DATABASE_URL=postgresql://app:secret@localhost:5432/app \
  -e DJANGO_SETTINGS_MODULE=config.settings.production \
  django-app:latest python manage.py migrate --noinput
```

### Static Files Collection

```bash
podman run --rm \
  -v ./staticfiles:/app/staticfiles:Z \
  django-app:latest python manage.py collectstatic --noinput
```

Use the `:Z` flag for SELinux compatibility in rootless Podman.

## Scaffolder Patterns

```yaml
patterns:
  quadlet: "deploy/django-app.container"
```

## Additional Dos

- DO use Gunicorn as the WSGI server -- never use `manage.py runserver` in production
- DO run `migrate --noinput` before starting the application
- DO run `collectstatic` as part of the build or deploy process
- DO use `:Z` volume flag for SELinux compatibility

## Additional Don'ts

- DON'T use `DEBUG=True` in production
- DON'T include development dependencies in the production image
- DON'T skip `--pod` when running with a database
- DON'T use `--privileged`
