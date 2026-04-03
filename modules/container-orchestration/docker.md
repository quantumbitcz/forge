# Docker

## Overview

Docker is the de facto standard for building, packaging, and running containerized applications. It provides a declarative image definition format (Dockerfile), a layered filesystem for efficient storage and distribution, and a runtime that isolates processes using Linux namespaces and cgroups (or their platform-native equivalents on macOS and Windows). Docker images are the universal artifact format for deployment — every major orchestrator (Kubernetes, ECS, Nomad, Cloud Run) consumes OCI-compliant images.

Use Docker for packaging any application that needs consistent, reproducible deployment across environments. This covers microservices, CLI tools, batch jobs, database migrations, static site builds, ML inference servers, and local development environments. Docker's multi-stage build system enables a clean separation between build-time dependencies (compilers, test frameworks, build tools) and runtime dependencies (the application binary plus minimal OS libraries), producing images that are small, secure, and fast to deploy.

Do not use Docker as a substitute for proper dependency management — containerizing a broken build does not fix it. Do not use Docker when the target platform cannot run containers (bare-metal embedded systems, iOS/Android devices). Do not use Docker in production without a container orchestrator — running `docker run` on a bare VM provides no scheduling, health monitoring, rolling updates, or resource limits. For local development, Docker is indispensable; for production, Docker provides the image format while orchestrators provide the operational guarantees.

Key differentiators: (1) BuildKit is the modern builder backend, enabling parallel stage execution, inline caching, cache mounts, secret mounts, and SSH forwarding — the legacy builder should never be used for new projects. (2) Multi-stage builds allow a single Dockerfile to compile, test, and package without leaking build tools into the runtime image. (3) Layer caching operates on instruction-level hashes — ordering Dockerfile instructions from least-frequently-changed to most-frequently-changed is the single highest-impact optimization. (4) Distroless and Chainguard images eliminate package managers and shells from runtime images, drastically reducing the CVE attack surface. (5) Image scanning tools (Trivy, Grype, Snyk) integrate into CI to catch vulnerabilities before deployment.

## Architecture Patterns

### Multi-Stage Builds

Multi-stage builds separate concerns into distinct stages within a single Dockerfile. Each stage starts with its own `FROM` instruction and produces a filesystem that subsequent stages can selectively copy from. This pattern eliminates the need for separate Dockerfiles for build vs. runtime, and it ensures that build-time dependencies (compilers, dev libraries, test tools) never reach the production image.

**Kotlin/Spring Boot multi-stage build:**
```dockerfile
# syntax=docker/dockerfile:1

# Stage 1: Build
FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /app

# Cache Gradle dependencies — these layers rarely change
COPY gradle/ gradle/
COPY gradlew build.gradle.kts settings.gradle.kts gradle.properties ./
COPY build-logic/ build-logic/
COPY gradle/libs.versions.toml gradle/libs.versions.toml
RUN --mount=type=cache,target=/root/.gradle/caches \
    --mount=type=cache,target=/root/.gradle/wrapper \
    ./gradlew dependencies --no-daemon

# Copy source and build
COPY src/ src/
RUN --mount=type=cache,target=/root/.gradle/caches \
    --mount=type=cache,target=/root/.gradle/wrapper \
    ./gradlew bootJar --no-daemon -x test

# Stage 2: Extract Spring Boot layers for optimized caching
FROM eclipse-temurin:21-jdk-alpine AS extract
WORKDIR /app
COPY --from=build /app/build/libs/*.jar app.jar
RUN java -Djarmode=layertools -jar app.jar extract

# Stage 3: Runtime
FROM eclipse-temurin:21-jre-alpine AS runtime
WORKDIR /app

# Security: run as non-root
RUN addgroup --system app && adduser --system --ingroup app app

# Spring Boot layered copy — most stable layers first
COPY --from=extract /app/dependencies/ ./
COPY --from=extract /app/spring-boot-loader/ ./
COPY --from=extract /app/snapshot-dependencies/ ./
COPY --from=extract /app/application/ ./

USER app
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
```

The three-stage pattern — build, extract, runtime — is critical for Spring Boot. The extraction stage uses `jarmode=layertools` to split the fat JAR into four directories ordered by change frequency. Docker layer caching means that when only application code changes, only the `application/` layer is rebuilt, while the `dependencies/` layer (the largest) is cached.

**Node.js/TypeScript multi-stage build:**
```dockerfile
# syntax=docker/dockerfile:1

FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    corepack enable && pnpm install --frozen-lockfile

FROM node:22-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN corepack enable && pnpm build

FROM gcr.io/distroless/nodejs22-debian12 AS runtime
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./

USER nonroot
EXPOSE 3000
CMD ["dist/main.js"]
```

### Layer Optimization

Docker images are composed of layers, each corresponding to a Dockerfile instruction. Layers are cached based on the hash of the instruction and its context (file contents for COPY/ADD, command string for RUN). Optimizing layer ordering is the single most impactful Dockerfile performance technique.

**Layer ordering principles:**

1. Instructions that change least frequently go first (base image, system packages, dependency manifests).
2. Dependency installation comes before source code copy — dependencies change less often than source code.
3. Source code copy comes last — every line after a cache-invalidating change must re-execute.
4. Use `.dockerignore` aggressively to prevent irrelevant files from invalidating the build context.

**Go multi-stage with optimal layering:**
```dockerfile
# syntax=docker/dockerfile:1

FROM golang:1.23-alpine AS build
WORKDIR /app

# Layer 1: Go module cache (changes rarely)
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# Layer 2: Source code (changes frequently)
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /server ./cmd/server

# Scratch for minimal attack surface
FROM scratch
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /server /server
USER 65534:65534
ENTRYPOINT ["/server"]
```

The Go example demonstrates building from `scratch` — an empty filesystem with zero packages, zero shells, and zero CVEs. The `ca-certificates.crt` copy is required for HTTPS client calls. The `USER 65534:65534` sets the `nobody` user without needing `adduser`.

**Critical `.dockerignore`:**
```
.git
.github
.idea
.vscode
node_modules
build/
dist/
target/
*.md
docker-compose*.yml
.env*
.forge/
```

### BuildKit Features

BuildKit is Docker's modern builder backend, enabled by default since Docker 23.0. It provides significant improvements over the legacy builder: parallel stage execution, enhanced caching, secret mounts, SSH forwarding, and inline cache export.

**Cache mounts** persist build caches across builds without baking them into image layers:
```dockerfile
# Package manager caches
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential libpq-dev

# Python pip cache
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements.txt

# Gradle cache
RUN --mount=type=cache,target=/root/.gradle/caches \
    --mount=type=cache,target=/root/.gradle/wrapper \
    ./gradlew build --no-daemon
```

**Secret mounts** expose secrets during build without persisting them in image layers:
```dockerfile
# Use a secret for private registry authentication
RUN --mount=type=secret,id=npmrc,target=/app/.npmrc \
    npm ci --production

# Use a secret for private Git repos
RUN --mount=type=ssh \
    git clone git@github.com:org/private-lib.git
```

**Inline cache export** enables CI cache reuse across builds:
```bash
# Build with inline cache metadata
docker build \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  -t myapp:latest .

# Subsequent build uses previous image as cache source
docker build \
  --cache-from myapp:latest \
  -t myapp:latest .
```

**Registry-based cache** for CI pipelines:
```bash
docker buildx build \
  --cache-from type=registry,ref=registry.example.com/myapp:cache \
  --cache-to type=registry,ref=registry.example.com/myapp:cache,mode=max \
  -t myapp:latest \
  --push .
```

### Security Hardening

Container security starts at build time and extends through runtime. The attack surface of a container image is the sum of all packages, libraries, and binaries included. Reducing image contents to the absolute minimum required for the application is the most effective security strategy.

**Non-root user pattern:**
```dockerfile
# Create a dedicated application user
RUN addgroup --system --gid 1001 app && \
    adduser --system --uid 1001 --ingroup app app

# Set ownership on application directory
COPY --chown=app:app --from=build /app/dist ./dist

# Switch to non-root before ENTRYPOINT
USER app
```

**Distroless and Chainguard base images:**
```dockerfile
# Distroless — Google-maintained, no shell, no package manager
FROM gcr.io/distroless/java21-debian12
FROM gcr.io/distroless/nodejs22-debian12
FROM gcr.io/distroless/static-debian12   # For Go, Rust static binaries
FROM gcr.io/distroless/cc-debian12       # For C/C++ with libc

# Chainguard — zero-CVE, SBOM-included, frequently updated
FROM cgr.dev/chainguard/jre:latest
FROM cgr.dev/chainguard/node:latest
FROM cgr.dev/chainguard/static:latest
FROM cgr.dev/chainguard/python:latest
```

**Image scanning in CI:**
```bash
# Trivy — comprehensive vulnerability scanner
trivy image --exit-code 1 --severity HIGH,CRITICAL myapp:latest

# Grype — Anchore's scanner
grype myapp:latest --fail-on high

# Docker Scout — built into Docker CLI
docker scout cves myapp:latest --exit-code --only-severity critical,high
```

**Read-only root filesystem at runtime:**
```yaml
# docker-compose.yml
services:
  app:
    image: myapp:latest
    read_only: true
    tmpfs:
      - /tmp
    security_opt:
      - no-new-privileges:true
```

### Image Tagging and Registry Strategy

Proper image tagging is essential for reproducible deployments, rollback capability, and audit trails. The `latest` tag is a mutable pointer that provides no guarantees about image contents — it should never be used in production deployment manifests.

**Tagging strategy:**
```bash
# Git SHA for immutable, traceable tags
docker build -t myapp:$(git rev-parse --short HEAD) .

# Semantic version for release milestones
docker build -t myapp:1.2.3 .

# Combined: version + SHA for maximum traceability
docker build -t myapp:1.2.3-abc1234 .

# CI pipeline example (GitHub Actions)
IMAGE_TAG="${GITHUB_SHA::7}"
docker build \
  -t registry.example.com/myapp:${IMAGE_TAG} \
  -t registry.example.com/myapp:latest \
  --push .
```

**SHA-pinned base images for production:**
```dockerfile
# Pin to digest for reproducible builds
FROM eclipse-temurin:21-jre-alpine@sha256:abc123...

# Renovate/Dependabot will update the digest automatically
```

## Configuration

### Development

Development Docker configuration prioritizes fast iteration, live reloading, and parity with production image structure.

```dockerfile
# Dockerfile.dev — development with hot reload
FROM node:22-alpine
WORKDIR /app

COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install

COPY . .
EXPOSE 3000
CMD ["pnpm", "dev"]
```

```yaml
# docker-compose.yml — development overrides
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    volumes:
      - .:/app
      - /app/node_modules    # Anonymous volume prevents host override
    environment:
      - NODE_ENV=development
    ports:
      - "3000:3000"
```

### Production

Production Docker configuration prioritizes minimal image size, security, and reproducibility.

```dockerfile
# Production Dockerfile checklist:
# 1. Pin base image to digest
# 2. Multi-stage build (build → runtime)
# 3. Non-root user
# 4. HEALTHCHECK instruction
# 5. No secrets in image layers
# 6. .dockerignore excludes build artifacts and VCS
# 7. Labels for metadata
# 8. Minimal runtime image (distroless/alpine/scratch)

FROM eclipse-temurin:21-jre-alpine@sha256:abc123... AS runtime
LABEL org.opencontainers.image.source="https://github.com/org/repo"
LABEL org.opencontainers.image.version="1.2.3"
LABEL org.opencontainers.image.description="Production API server"

RUN addgroup --system --gid 1001 app && \
    adduser --system --uid 1001 --ingroup app app

WORKDIR /app
COPY --from=build --chown=app:app /app/build/libs/app.jar ./app.jar

USER app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", \
    "-XX:MaxRAMPercentage=75.0", \
    "-XX:+UseZGC", \
    "-jar", "app.jar"]
```

## Performance

Image build performance depends on layer caching, BuildKit parallelism, and build context size. Runtime performance depends on resource limits, the JVM/runtime configuration, and filesystem overhead.

**Build performance:**
- Order Dockerfile instructions from least to most frequently changed. Dependency installation (which changes weekly) should precede source code copy (which changes every commit).
- Use BuildKit cache mounts (`--mount=type=cache`) for package manager caches (Gradle, npm, pip, Go modules). This avoids re-downloading dependencies when the cache layer is invalidated by an unrelated change.
- Minimize build context with `.dockerignore`. A 500MB build context that includes `node_modules/` or `.git/` adds seconds of transfer time to every build, even when those files are never used.
- Use `docker buildx bake` for parallel multi-image builds in monorepos.
- Enable BuildKit's inline cache (`BUILDKIT_INLINE_CACHE=1`) or registry cache (`--cache-to type=registry`) to share caches across CI runners.

**Runtime performance:**
- Set memory limits in the orchestrator, not in the Dockerfile. JVM applications should use `-XX:MaxRAMPercentage=75.0` to respect container memory limits while leaving headroom for off-heap allocations.
- Use `--cpus` or orchestrator CPU limits. Without limits, a container can starve other containers on the same host.
- For JVM applications, use `-XX:+UseZGC` or `-XX:+UseG1GC` and let the JVM auto-tune based on container limits. Do not set `-Xmx` explicitly when using `MaxRAMPercentage`.
- Alpine-based images use musl libc, which can cause performance differences compared to glibc for some workloads (notably DNS resolution and memory allocation patterns). Test performance-critical applications on both Alpine and Debian-slim base images.

## Security

Container security operates at four levels: image contents, build pipeline, runtime configuration, and registry access.

**Image contents:** Use minimal base images (distroless, Chainguard, Alpine, scratch). Every additional package is an additional CVE surface. Scan images with Trivy or Grype in CI and block deployments with HIGH or CRITICAL vulnerabilities. Pin base images to digests, not tags, because tags are mutable.

**Build pipeline:** Never embed secrets in Dockerfile instructions (ARG, ENV, COPY). Use BuildKit secret mounts (`--mount=type=secret`) for build-time secrets. Use multi-stage builds to ensure build tools (compilers, dev dependencies) do not reach production images.

**Runtime configuration:** Run containers as non-root (`USER` instruction or orchestrator-level `runAsNonRoot`). Set `read_only: true` on the root filesystem and use `tmpfs` mounts for temporary files. Apply `no-new-privileges` to prevent privilege escalation via setuid binaries. Drop all capabilities and add back only what the application requires.

**Registry access:** Use private registries with authentication. Enable content trust (Docker Content Trust / Notary) for image signing. Use image pull policies that prevent unsigned or unscanned images from reaching production.

## Testing

**Dockerfile linting:**
```bash
# Hadolint — Dockerfile best-practice linter
hadolint Dockerfile
hadolint --failure-threshold warning Dockerfile

# In CI (GitHub Actions)
- uses: hadolint/hadolint-action@v3
  with:
    dockerfile: Dockerfile
    failure-threshold: warning
```

**Image structure tests:**
```bash
# Google container-structure-test
container-structure-test test \
  --image myapp:latest \
  --config structure-test.yaml
```

```yaml
# structure-test.yaml
schemaVersion: "2.0.0"
metadataTest:
  user: "app"
  exposedPorts: ["8080"]
  entrypoint: ["java"]
fileExistenceTests:
  - name: "Application JAR exists"
    path: "/app/app.jar"
    shouldExist: true
fileContentTests:
  - name: "No shell in image"
    path: "/bin/sh"
    shouldExist: false
commandTests:
  - name: "No package manager"
    command: "which"
    args: ["apt-get"]
    exitCode: 1
```

**Integration testing with Testcontainers:**
```kotlin
@Testcontainers
class AppContainerTest {
    companion object {
        @Container
        val app = GenericContainer("myapp:test")
            .withExposedPorts(8080)
            .waitingFor(Wait.forHttp("/actuator/health").forStatusCode(200))
    }

    @Test
    fun `health endpoint responds`() {
        val url = "http://${app.host}:${app.getMappedPort(8080)}/actuator/health"
        val response = URI(url).toURL().readText()
        assertThat(response).contains("UP")
    }
}
```

## Dos

- Use multi-stage builds for every production image — separate build dependencies from runtime.
- Pin base images to SHA digests in production Dockerfiles for reproducible builds.
- Run containers as non-root using the `USER` instruction with a dedicated application user.
- Include a `HEALTHCHECK` instruction so orchestrators can detect unhealthy containers.
- Use BuildKit cache mounts for package manager caches to avoid redundant downloads.
- Maintain a strict `.dockerignore` that excludes `.git`, `node_modules`, `build/`, `target/`, and IDE files.
- Scan images in CI with Trivy or Grype and fail builds on HIGH/CRITICAL vulnerabilities.
- Use OCI labels (`org.opencontainers.image.*`) for image metadata (source repo, version, description).
- Prefer `COPY` over `ADD` unless extracting a tar archive — `ADD` has implicit behaviors that cause surprises.
- Use `ENTRYPOINT` for the main command and `CMD` for default arguments, enabling argument override without replacing the command.

## Don'ts

- Do not use `FROM image:latest` in production — `latest` is mutable and breaks reproducibility.
- Do not run containers as root in production — every container process should run as a non-root user.
- Do not embed secrets (passwords, API keys, tokens) in `ENV`, `ARG`, or `COPY` instructions — they persist in image layers.
- Do not install unnecessary packages (curl, vim, wget) in production images — each package expands the CVE surface.
- Do not use `ADD` for copying local files — use `COPY` for predictable behavior.
- Do not use the legacy builder (pre-BuildKit) — it lacks parallelism, cache mounts, secret mounts, and inline caching.
- Do not ignore `.dockerignore` — a missing or incomplete file sends the entire project directory as build context.
- Do not use `MAINTAINER` — it is deprecated; use `LABEL org.opencontainers.image.authors` instead.
- Do not chain unrelated `RUN` commands into a single layer to "save layers" — modern BuildKit handles layers efficiently, and readability matters more than saving a few bytes.
- Do not use `docker commit` to create production images — always build from a Dockerfile for reproducibility.
