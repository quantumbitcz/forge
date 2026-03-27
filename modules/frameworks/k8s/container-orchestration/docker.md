# Docker with Kubernetes

> Extends `modules/container-orchestration/docker.md` with Kubernetes-oriented container image patterns.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

```dockerfile
# Base image for Kubernetes workloads
FROM alpine:3.20 AS runtime

RUN addgroup -S app && adduser -S app -G app

COPY --from=builder /app/bin/server /usr/local/bin/server

USER app:app

EXPOSE 8080
HEALTHCHECK NONE

ENTRYPOINT ["/usr/local/bin/server"]
```

In Kubernetes, health checks are defined in pod specs (livenessProbe, readinessProbe, startupProbe). Docker's `HEALTHCHECK` is ignored by Kubernetes -- omit it to avoid confusion.

## Framework-Specific Patterns

### Image Tagging for Kubernetes

```bash
# Tag with Git SHA for immutable deployments
docker build -t registry.example.com/app:$(git rev-parse --short HEAD) .
docker tag registry.example.com/app:$(git rev-parse --short HEAD) registry.example.com/app:latest

# Pin to SHA digest in production manifests
image: registry.example.com/app@sha256:abc123...
```

Kubernetes manifests should reference images by digest in production. Tags are mutable -- digests are not.

### Multi-Architecture Builds

```bash
docker buildx create --name multiarch --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t registry.example.com/app:latest \
  --push .
```

Kubernetes clusters may run mixed architectures (amd64 control plane, arm64 worker nodes). Multi-arch images ensure portability.

### Distroless and Scratch Images

```dockerfile
# For Go/Rust static binaries
FROM scratch
COPY --from=builder /app/bin/server /server
USER 65534:65534
ENTRYPOINT ["/server"]

# For JVM/Python/Node.js
FROM gcr.io/distroless/java21-debian12
FROM gcr.io/distroless/python3-debian12
FROM gcr.io/distroless/nodejs22-debian12
```

Distroless images have no shell, package manager, or utilities. This reduces the attack surface but makes debugging harder -- use ephemeral debug containers (`kubectl debug`) instead.

### Init Containers for Migrations

```yaml
initContainers:
  - name: migrate
    image: registry.example.com/app:latest
    command: ["migrate", "up"]
```

Kubernetes init containers run before the main container starts. Use them for database migrations, config initialization, or waiting for dependencies.

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
```

## Additional Dos

- DO pin images by SHA digest in production Kubernetes manifests
- DO build multi-architecture images for mixed-arch clusters
- DO use distroless or scratch base images for minimal attack surface
- DO omit Docker `HEALTHCHECK` -- Kubernetes uses its own probe system

## Additional Don'ts

- DON'T use `latest` tag in production manifests -- it is mutable and non-deterministic
- DON'T include debugging tools in production images -- use `kubectl debug` ephemeral containers
- DON'T embed secrets in images -- use Kubernetes Secrets mounted at runtime
- DON'T use Docker `HEALTHCHECK` in Kubernetes-targeted images -- it is ignored
