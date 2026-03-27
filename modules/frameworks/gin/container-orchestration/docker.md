# Docker with Gin

> Extends `modules/container-orchestration/docker.md` with Gin/Go containerization patterns.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

```dockerfile
FROM golang:1.23-alpine AS builder
WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o server ./cmd/server

FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app/server /server

EXPOSE 8080
ENTRYPOINT ["/server"]
```

`go mod download` caches dependencies in a separate layer. `CGO_ENABLED=0` produces a static binary. `-ldflags="-s -w"` strips debug info for smaller binaries.

## Framework-Specific Patterns

### Gin Production Mode

```dockerfile
ENV GIN_MODE=release
```

Set `GIN_MODE=release` to disable debug logging and colored output in production.

### Health Check

```go
r.GET("/health", func(c *gin.Context) {
    c.JSON(200, gin.H{"status": "ok"})
})
```

Use `scratch` base -- no shell for HEALTHCHECK. Rely on orchestrator probes.

### Distroless Alternative

```dockerfile
FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/server /server
ENTRYPOINT ["/server"]
```

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
```

## Additional Dos

- DO use `CGO_ENABLED=0` for static binaries that run on `scratch`
- DO copy CA certificates from the builder for HTTPS support
- DO set `GIN_MODE=release` in production
- DO use `-ldflags="-s -w"` to reduce binary size

## Additional Don'ts

- DON'T include the Go toolchain in the runtime image
- DON'T use `go run` in production -- use the compiled binary
- DON'T enable CGO when targeting `scratch` or `distroless`
- DON'T skip CA certificates when the binary makes HTTPS requests
