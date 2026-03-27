# Docker with Go stdlib

> Extends `modules/container-orchestration/docker.md` with Go stdlib containerization patterns.
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

Pure Go with `CGO_ENABLED=0` produces a fully static binary. No framework runtime needed.

## Framework-Specific Patterns

### net/http Server Configuration

```go
srv := &http.Server{
    Addr:         ":8080",
    Handler:      mux,
    ReadTimeout:  5 * time.Second,
    WriteTimeout: 10 * time.Second,
    IdleTimeout:  120 * time.Second,
}
```

Always set timeouts on `http.Server` in production to prevent resource exhaustion.

### Graceful Shutdown

```go
ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
defer stop()

go srv.ListenAndServe()
<-ctx.Done()
srv.Shutdown(context.Background())
```

Handle `SIGTERM` for Docker stop signals.

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
```

## Additional Dos

- DO use `CGO_ENABLED=0` for static binaries
- DO set read/write/idle timeouts on `http.Server`
- DO handle `SIGTERM` for graceful shutdown
- DO copy CA certificates for HTTPS support

## Additional Don'ts

- DON'T use `http.ListenAndServe` without timeouts in production
- DON'T include the Go toolchain in the runtime image
- DON'T skip CA certificates when making outbound HTTPS calls
