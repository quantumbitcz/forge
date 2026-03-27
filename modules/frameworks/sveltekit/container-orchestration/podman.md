# Podman with SvelteKit

> Extends `modules/container-orchestration/podman.md` with SvelteKit adapter-node patterns.
> Generic Podman conventions (rootless containers, pod management, systemd integration) are NOT repeated here.

## Integration Setup

### Building with Podman

```bash
# Build the SvelteKit image (same Dockerfile as Docker)
podman build -t sveltekit-app:latest .

# Run the container
podman run -d \
  --name sveltekit-app \
  -p 3000:3000 \
  -e NODE_ENV=production \
  -e APP_API_URL=http://localhost:8080 \
  sveltekit-app:latest
```

Podman uses the same Dockerfile format as Docker. The SvelteKit `adapter-node` Dockerfile works without modification.

## Framework-Specific Patterns

### Rootless Execution

```bash
# SvelteKit runs on port 3000 (unprivileged, no root needed)
podman run --userns=keep-id \
  -p 3000:3000 \
  -e PORT=3000 \
  sveltekit-app:latest
```

SvelteKit's default port (3000) is unprivileged, making it ideal for rootless Podman. No port remapping or `setcap` needed.

### Pod with Backend Services

```bash
# Create a pod with shared network namespace
podman pod create --name app-stack -p 3000:3000 -p 8080:8080

# Run the API backend
podman run -d --pod app-stack \
  --name api \
  registry.example.com/api:latest

# Run the SvelteKit frontend
podman run -d --pod app-stack \
  --name frontend \
  -e APP_API_URL=http://localhost:8080 \
  sveltekit-app:latest
```

Within a Podman pod, containers share `localhost`. SvelteKit's server-side load functions can reach the API at `localhost:8080`.

### Systemd Integration

```bash
# Generate a systemd service for the container
podman generate systemd --new --name sveltekit-app > ~/.config/systemd/user/sveltekit-app.service
systemctl --user enable --now sveltekit-app.service
```

### Podman Compose

```yaml
# compose.yaml (compatible with podman-compose)
services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      NODE_ENV: production
      APP_API_URL: http://api:8080
    depends_on:
      - api

  api:
    image: registry.example.com/api:latest
    ports:
      - "8080:8080"
```

```bash
podman-compose up -d
```

## Scaffolder Patterns

```yaml
patterns:
  containerfile: "Dockerfile"
  compose: "compose.yaml"
```

## Additional Dos

- DO use rootless Podman for SvelteKit -- port 3000 needs no root privileges
- DO use Podman pods for multi-container stacks with shared networking
- DO generate systemd units for production service management
- DO use the same Dockerfile as Docker -- Podman is OCI-compatible

## Additional Don'ts

- DON'T use `--privileged` for SvelteKit containers -- they need no elevated permissions
- DON'T map to port 80 in rootless mode without `sysctl` adjustments
- DON'T forget `--userns=keep-id` when volume-mounting with correct ownership
