# Podman with Axum

> Extends `modules/container-orchestration/podman.md` with Axum/Rust containerization patterns.
> Generic Podman conventions (rootless containers, pod definitions, systemd integration) are NOT repeated here.

## Integration Setup

### Build with Podman

```bash
podman build -t axum-app:latest .
podman run -d --name axum-app -p 3000:3000 axum-app:latest
```

Podman uses the same Dockerfile as Docker. The multi-stage Rust build produces a static binary that runs on `scratch`.

## Framework-Specific Patterns

### Rootless Static Binary

```bash
podman run -d \
  --name axum-app \
  --user 1000:1000 \
  -p 3000:3000 \
  -e RUST_LOG=info \
  -e DATABASE_URL_FILE=/run/secrets/db-url \
  axum-app:latest
```

Rust static binaries run as non-root without any runtime dependencies. Ideal for Podman's rootless mode.

### Pod with Database

```bash
podman pod create --name axum-pod -p 3000:3000 -p 5432:5432

podman run -d --pod axum-pod --name postgres \
  -e POSTGRES_DB=app -e POSTGRES_USER=app -e POSTGRES_PASSWORD=secret \
  postgres:16-alpine

podman run -d --pod axum-pod --name axum-app \
  -e DATABASE_URL=postgresql://app:secret@localhost:5432/app \
  axum-app:latest
```

In a pod, containers share the network namespace. The app connects to PostgreSQL via `localhost`.

### Quadlet (Systemd Integration)

```ini
# ~/.config/containers/systemd/axum-app.container
[Container]
Image=registry.example.com/axum-app:latest
PublishPort=3000:3000
Environment=RUST_LOG=info
Secret=db-url,type=env,target=DATABASE_URL

[Service]
Restart=always

[Install]
WantedBy=default.target
```

Quadlet generates systemd units from container definitions. Use for production deployments on single hosts.

## Scaffolder Patterns

```yaml
patterns:
  quadlet: "deploy/axum-app.container"
```

## Additional Dos

- DO use rootless Podman -- Rust static binaries have zero runtime dependencies
- DO use Podman pods for multi-container deployments
- DO use Quadlet for systemd-managed production deployments
- DO use `scratch` base image for minimal attack surface

## Additional Don'ts

- DON'T use `--privileged` -- Rust binaries never need it
- DON'T assume Docker socket exists -- Podman uses its own socket
- DON'T skip secrets management -- use Podman secrets or file mounts
