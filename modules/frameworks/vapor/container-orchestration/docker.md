# Docker with Vapor

> Extends `modules/container-orchestration/docker.md` with Vapor/Swift containerization patterns.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

### Multi-Stage Dockerfile

```dockerfile
# Stage 1: Build
FROM swift:6.0 AS builder
WORKDIR /app

COPY Package.swift Package.resolved ./
RUN swift package resolve

COPY . .
RUN swift build -c release

# Stage 2: Runtime
FROM ubuntu:24.04
WORKDIR /app

RUN apt-get update && apt-get install -y \
    libcurl4 libxml2 libz3-4 \
    && rm -rf /var/lib/apt/lists/*

RUN addgroup --system vapor && adduser --system --group vapor

COPY --from=builder /app/.build/release/App /app/App
COPY --from=builder /app/Public /app/Public
COPY --from=builder /app/Resources /app/Resources

USER vapor:vapor

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

ENTRYPOINT ["./App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
```

Swift requires shared libraries at runtime. Use Ubuntu as the base and install only the minimal shared libs.

## Framework-Specific Patterns

### Vapor Environment Configuration

```dockerfile
ENV VAPOR_ENV=production
CMD ["./App", "serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
```

### Fluent Migration in Entrypoint

```bash
#!/usr/bin/env bash
set -e
./App migrate --yes
exec ./App serve --env production --hostname 0.0.0.0 --port 8080
```

### Slim Runtime with Swift Libraries

```dockerfile
FROM swift:6.0-slim AS runtime
```

`swift:6.0-slim` includes only the Swift runtime libraries. Smaller than Ubuntu but larger than `scratch`.

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
```

## Additional Dos

- DO resolve packages before copying source for layer caching
- DO use Ubuntu or `swift-slim` as the runtime base -- Swift needs shared libs
- DO use `--env production` for Vapor production mode
- DO install only minimal shared libraries in the runtime stage

## Additional Don'ts

- DON'T use `scratch` -- Swift binaries need shared libraries
- DON'T include the Swift SDK in the runtime image
- DON'T run as root -- create a `vapor` user
- DON'T copy `.build/` entirely -- only copy the release binary
