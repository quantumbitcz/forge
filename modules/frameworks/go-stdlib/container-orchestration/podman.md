# Podman with Go stdlib

> Extends `modules/container-orchestration/podman.md` with Go stdlib containerization patterns.
> Generic Podman conventions (rootless containers, pod definitions, systemd integration) are NOT repeated here.

## Integration Setup

```bash
podman build -t go-app:latest .
podman run -d --name go-app -p 8080:8080 go-app:latest
```

## Framework-Specific Patterns

### Rootless Static Binary

Go static binaries (`CGO_ENABLED=0`) run as non-root without any runtime dependencies. Ideal for Podman's rootless mode.

```bash
podman run -d --user 1000:1000 -p 8080:8080 go-app:latest
```

### Pod with Database

```bash
podman pod create --name go-pod -p 8080:8080 -p 5432:5432

podman run -d --pod go-pod --name postgres \
  -e POSTGRES_DB=app -e POSTGRES_USER=app -e POSTGRES_PASSWORD=secret \
  postgres:16-alpine

podman run -d --pod go-pod --name go-app \
  -e DATABASE_URL=postgresql://app:secret@localhost:5432/app \
  go-app:latest
```

### Quadlet Integration

```ini
[Container]
Image=registry.example.com/go-app:latest
PublishPort=8080:8080
Secret=db-url,type=env,target=DATABASE_URL

[Service]
Restart=always

[Install]
WantedBy=default.target
```

## Scaffolder Patterns

```yaml
patterns:
  quadlet: "deploy/go-app.container"
```

## Additional Dos

- DO use rootless Podman
- DO use `scratch` base image
- DO use Quadlet for systemd integration

## Additional Don'ts

- DON'T use `--privileged`
- DON'T skip secrets management
