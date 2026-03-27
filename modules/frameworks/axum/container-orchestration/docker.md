# Docker with Axum

> Extends `modules/container-orchestration/docker.md` with Axum/Rust containerization patterns.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

### Multi-Stage Dockerfile (Static Binary)

```dockerfile
FROM rust:latest AS builder
WORKDIR /app

RUN rustup target add x86_64-unknown-linux-musl

COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release --target x86_64-unknown-linux-musl
RUN rm -rf src

COPY src/ ./src/
RUN touch src/main.rs
RUN cargo build --release --target x86_64-unknown-linux-musl

FROM scratch
COPY --from=builder /app/target/x86_64-unknown-linux-musl/release/app /app
EXPOSE 3000
ENTRYPOINT ["/app"]
```

The dummy `main.rs` trick builds dependencies first, caching them in a Docker layer. Only application code triggers a rebuild.

## Framework-Specific Patterns

### Distroless Alternative

```dockerfile
FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/target/x86_64-unknown-linux-musl/release/app /app
EXPOSE 3000
ENTRYPOINT ["/app"]
```

Distroless provides CA certificates and timezone data that `scratch` lacks. Use when the application makes HTTPS requests.

### Health Check (Distroless)

Since `scratch` and `distroless` have no shell, health checks must be done by the orchestrator. For development, use a Rust-based health check binary or the application itself:

```rust
// Built-in health endpoint
async fn health() -> &'static str { "ok" }
```

### sccache in Docker Build

```dockerfile
ENV RUSTC_WRAPPER=/usr/local/bin/sccache
ENV SCCACHE_DIR=/app/.sccache
RUN cargo install sccache
```

### Static Linking Flags

```dockerfile
ENV RUSTFLAGS='-C target-feature=+crt-static'
RUN cargo build --release --target x86_64-unknown-linux-musl
```

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
```

## Additional Dos

- DO use multi-stage builds with dependency caching via dummy `main.rs`
- DO build static binaries for `scratch` or `distroless` base images
- DO use `x86_64-unknown-linux-musl` target for fully static binaries
- DO use distroless when HTTPS or TLS is needed

## Additional Don'ts

- DON'T include the Rust toolchain in the runtime image
- DON'T use `cargo run` in production -- copy the release binary
- DON'T skip the dependency caching trick -- Rust compilation is slow
- DON'T use `scratch` when the binary needs CA certificates
