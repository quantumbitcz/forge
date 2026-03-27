# Podman with Gin

> Extends `modules/container-orchestration/podman.md` with Gin/Go containerization patterns.
> Generic Podman conventions (rootless containers, pod definitions, systemd integration) are NOT repeated here.

## Integration Setup

```bash
podman build -t gin-app:latest .
podman run -d --name gin-app -p 8080:8080 -e GIN_MODE=release gin-app:latest
```

## Framework-Specific Patterns

### Rootless Static Binary

```bash
podman run -d \
  --name gin-app \
  --user 1000:1000 \
  -p 8080:8080 \
  -e GIN_MODE=release \
  gin-app:latest
```

Go static binaries run as non-root without any runtime dependencies.

### Pod with Database

```bash
podman pod create --name gin-pod -p 8080:8080 -p 5432:5432

podman run -d --pod gin-pod --name postgres \
  -e POSTGRES_DB=app -e POSTGRES_USER=app -e POSTGRES_PASSWORD=secret \
  postgres:16-alpine

podman run -d --pod gin-pod --name gin-app \
  -e DATABASE_URL=postgresql://app:secret@localhost:5432/app \
  -e GIN_MODE=release \
  gin-app:latest
```

### Quadlet Integration

```ini
[Container]
Image=registry.example.com/gin-app:latest
PublishPort=8080:8080
Environment=GIN_MODE=release
Secret=db-url,type=env,target=DATABASE_URL

[Service]
Restart=always

[Install]
WantedBy=default.target
```

## Scaffolder Patterns

```yaml
patterns:
  quadlet: "deploy/gin-app.container"
```

## Additional Dos

- DO use rootless Podman -- Go static binaries have zero dependencies
- DO set `GIN_MODE=release` in production
- DO use Quadlet for systemd-managed deployments
- DO use `scratch` base image

## Additional Don'ts

- DON'T use `--privileged`
- DON'T set `GIN_MODE=debug` in production
- DON'T skip secrets management
