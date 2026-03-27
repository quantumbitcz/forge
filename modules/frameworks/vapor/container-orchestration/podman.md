# Podman with Vapor

> Extends `modules/container-orchestration/podman.md` with Vapor/Swift containerization patterns.
> Generic Podman conventions (rootless containers, pod definitions, systemd integration) are NOT repeated here.

## Integration Setup

```bash
podman build -t vapor-app:latest .
podman run -d --name vapor-app -p 8080:8080 -e VAPOR_ENV=production vapor-app:latest
```

## Framework-Specific Patterns

### Pod with Database

```bash
podman pod create --name vapor-pod -p 8080:8080 -p 5432:5432

podman run -d --pod vapor-pod --name postgres \
  -e POSTGRES_DB=app -e POSTGRES_USER=app -e POSTGRES_PASSWORD=secret \
  postgres:16-alpine

podman run -d --pod vapor-pod --name vapor-app \
  -e DATABASE_URL=postgresql://app:secret@localhost:5432/app \
  -e VAPOR_ENV=production \
  vapor-app:latest
```

### Quadlet Integration

```ini
[Container]
Image=registry.example.com/vapor-app:latest
PublishPort=8080:8080
Environment=VAPOR_ENV=production
Secret=db-url,type=env,target=DATABASE_URL

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### Fluent Migration

```bash
podman run --rm --pod vapor-pod \
  -e DATABASE_URL=postgresql://app:secret@localhost:5432/app \
  vapor-app:latest ./App migrate --yes
```

## Scaffolder Patterns

```yaml
patterns:
  quadlet: "deploy/vapor-app.container"
```

## Additional Dos

- DO use Podman pods for multi-container setups
- DO use Quadlet for systemd-managed production deployments
- DO set `VAPOR_ENV=production` in production
- DO run Fluent migrations before starting the app

## Additional Don'ts

- DON'T use `scratch` -- Swift needs shared libraries
- DON'T skip Fluent migrations
- DON'T use development environment in production
