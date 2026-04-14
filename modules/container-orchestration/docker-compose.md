# Docker Compose

## Overview

Docker Compose is a tool for defining and running multi-container applications using a declarative YAML configuration file. It enables developers to describe an entire application stack — services, networks, volumes, and their interdependencies — in a single `docker-compose.yml` (or `compose.yml`) file and manage it with simple commands (`docker compose up`, `docker compose down`). Compose is the standard tool for local development environments, integration testing, and small-scale deployments where a full container orchestrator like Kubernetes is unnecessary.

Docker Compose V2 is the current version, implemented as a Docker CLI plugin (`docker compose`) rather than a standalone Python binary (`docker-compose`). V2 is faster, supports profiles for optional services, watch mode for hot-reload development, and integrates natively with Docker Desktop and BuildKit. The standalone `docker-compose` binary (V1) is deprecated and no longer maintained — all new projects must use V2 syntax (`docker compose` with a space, not a hyphen).

Use Docker Compose for local development environments that mirror production topology (application + database + cache + message broker), integration testing in CI pipelines, small single-host deployments (personal projects, internal tools), and docker-based development workflows with file watching and hot reload. Compose excels at codifying the "how do I run this locally?" question — a new developer should be able to `git clone` and `docker compose up` to get a working environment.

Do not use Docker Compose for production deployments at scale — it provides no scheduling, no rolling updates, no multi-host networking, and no self-healing. For production, use Kubernetes, Docker Swarm, or a managed container service (ECS, Cloud Run). Do not use Compose to manage infrastructure that needs high availability. Do not use Compose as a replacement for Testcontainers in integration tests — Testcontainers provides programmatic container lifecycle management, randomized ports, and test-scoped cleanup that Compose cannot match.

## Architecture Patterns

### V2 Service Definitions

Compose V2 uses the top-level `services`, `networks`, and `volumes` keys without a `version` field. The `version` key is deprecated and ignored by Compose V2 — including it generates a warning. Services define containers, their build context or image reference, environment variables, ports, volumes, dependencies, and health checks.

**Full-stack application (Spring Boot + PostgreSQL + Redis):**
```yaml
# compose.yml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: runtime
      args:
        BUILDKIT_INLINE_CACHE: 1
    ports:
      - "8080:8080"
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://db:5432/myapp
      SPRING_DATASOURCE_USERNAME: myapp
      SPRING_DATASOURCE_PASSWORD: secret
      SPRING_DATA_REDIS_HOST: redis
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080/actuator/health"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 30s
    restart: unless-stopped

  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: myapp
      POSTGRES_PASSWORD: secret
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./docker/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U myapp -d myapp"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    command: redis-server --requirepass secret --maxmemory 128mb --maxmemory-policy allkeys-lru
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "secret", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    volumes:
      - redis_data:/data

volumes:
  postgres_data:
  redis_data:
```

The `depends_on` with `condition: service_healthy` is the critical pattern. Without conditions, Compose only waits for the container to start, not for the service inside it to be ready. PostgreSQL might take several seconds to initialize; a health check ensures the application container does not start until the database is actually accepting connections.

### Health Checks and Dependency Management

Health checks in Compose serve two purposes: (1) they gate dependent service startup via `depends_on` conditions, and (2) they provide ongoing readiness signals for `restart: unless-stopped` policies.

**Health check patterns for common services:**
```yaml
services:
  # PostgreSQL
  postgres:
    image: postgres:17-alpine
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  # MySQL/MariaDB
  mysql:
    image: mysql:8.4
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${MYSQL_ROOT_PASSWORD}"]
      interval: 10s
      timeout: 5s
      retries: 5

  # MongoDB
  mongo:
    image: mongo:7
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Kafka (via Redpanda for local dev)
  redpanda:
    image: redpandadata/redpanda:v24.3.1
    healthcheck:
      test: ["CMD", "rpk", "cluster", "health"]
      interval: 15s
      timeout: 10s
      retries: 5

  # Elasticsearch
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.17.0
    healthcheck:
      test: ["CMD-SHELL", "curl -s http://localhost:9200/_cluster/health | grep -q '\"status\":\"green\\|yellow\"'"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  # Application depending on all infrastructure
  app:
    depends_on:
      postgres:
        condition: service_healthy
      redpanda:
        condition: service_healthy
      elasticsearch:
        condition: service_healthy
        restart: true   # Restart app if elasticsearch restarts
```

The `restart: true` option on `depends_on` (Compose V2.22+) makes dependent services restart when their dependency restarts. This is useful for services that hold connections — if PostgreSQL restarts, the application should restart to re-establish connections rather than operating with stale connection pools.

### Profiles for Optional Services

Profiles group services into named sets that are only started when explicitly requested. This pattern is ideal for optional development tools (monitoring, debugging, seeding) that not every developer needs running all the time.

```yaml
services:
  app:
    build: .
    ports:
      - "8080:8080"

  db:
    image: postgres:17-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data

  # Only started with: docker compose --profile monitoring up
  prometheus:
    image: prom/prometheus:v2.54.1
    profiles: ["monitoring"]
    volumes:
      - ./docker/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:11.4.0
    profiles: ["monitoring"]
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
    ports:
      - "3000:3000"
    depends_on:
      - prometheus

  # Only started with: docker compose --profile debug up
  pgadmin:
    image: dpage/pgadmin4:8.14
    profiles: ["debug"]
    environment:
      PGADMIN_DEFAULT_EMAIL: admin@local.dev
      PGADMIN_DEFAULT_PASSWORD: admin
    ports:
      - "5050:80"

  # Only started with: docker compose --profile seed up
  seed:
    build:
      context: .
      dockerfile: Dockerfile
      target: build
    profiles: ["seed"]
    command: ["./gradlew", "flywayMigrate", "seedData"]
    depends_on:
      db:
        condition: service_healthy

volumes:
  postgres_data:
```

Usage:
```bash
# Core services only (app + db)
docker compose up -d

# Core + monitoring stack
docker compose --profile monitoring up -d

# Core + all optional services
docker compose --profile monitoring --profile debug up -d

# Run one-off seed task
docker compose --profile seed run --rm seed
```

### Watch Mode for Development

Compose Watch (V2.22+) provides file synchronization between host and container, enabling hot-reload workflows without bind mounts. This solves the performance problems of bind mounts on MacOS (where Docker Desktop uses a Linux VM) and the `node_modules` conflict problem.

```yaml
services:
  frontend:
    build:
      context: ./frontend
      target: dev
    ports:
      - "5173:5173"
    develop:
      watch:
        # Sync source files — triggers hot module replacement
        - action: sync
          path: ./frontend/src
          target: /app/src

        # Rebuild on dependency changes
        - action: rebuild
          path: ./frontend/package.json

        # Sync public assets
        - action: sync
          path: ./frontend/public
          target: /app/public

  backend:
    build:
      context: ./backend
      target: dev
    ports:
      - "8080:8080"
    develop:
      watch:
        # Sync source — Spring DevTools handles hot reload
        - action: sync
          path: ./backend/src
          target: /app/src

        # Full rebuild on dependency changes
        - action: rebuild
          path: ./backend/build.gradle.kts

        # Full rebuild on version catalog changes
        - action: rebuild
          path: ./backend/gradle/libs.versions.toml
```

```bash
# Start with watch mode
docker compose watch

# Or combine with up
docker compose up --watch
```

The three watch actions serve different purposes: `sync` copies changed files into the running container (fast, no restart), `sync+restart` copies files and restarts the container process, and `rebuild` triggers a full image rebuild and container recreation (slow, for dependency changes).

### Override Files and Environment Separation

Compose supports layered configuration through override files and environment-specific configurations. The default merge order is `compose.yml` → `compose.override.yml`. Additional files can be specified with `-f` flags or the `COMPOSE_FILE` environment variable.

**Base configuration (`compose.yml`):**
```yaml
services:
  app:
    image: registry.example.com/myapp:${APP_VERSION:-latest}
    restart: unless-stopped
    environment:
      SPRING_PROFILES_ACTIVE: ${SPRING_PROFILE:-default}
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080/actuator/health"]
      interval: 30s
      timeout: 5s
      retries: 3
```

**Development override (`compose.override.yml`):**
```yaml
services:
  app:
    build:
      context: .
      target: dev
    ports:
      - "8080:8080"
      - "5005:5005"   # Remote debug
    environment:
      SPRING_PROFILES_ACTIVE: local
      JAVA_TOOL_OPTIONS: "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005"
    volumes:
      - ./src:/app/src
```

**CI override (`compose.ci.yml`):**
```yaml
services:
  app:
    build:
      context: .
      target: runtime
    environment:
      SPRING_PROFILES_ACTIVE: test
    # No ports exposed — tests connect via Docker network
```

```bash
# Development (uses compose.yml + compose.override.yml automatically)
docker compose up

# CI (explicit file list, skips override)
docker compose -f compose.yml -f compose.ci.yml up -d
```

**Environment variables** in `.env` files:
```bash
# .env (loaded automatically by Compose)
APP_VERSION=1.2.3
POSTGRES_PASSWORD=changeme
SPRING_PROFILE=local
COMPOSE_PROJECT_NAME=myapp
```

## Configuration

### Development

Development configuration prioritizes fast feedback loops, debugger access, and infrastructure visibility.

```yaml
services:
  app:
    build:
      context: .
      target: dev
    ports:
      - "8080:8080"    # Application
      - "5005:5005"    # Java remote debug
    environment:
      SPRING_PROFILES_ACTIVE: local
      JAVA_TOOL_OPTIONS: >-
        -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005
        -XX:+UseZGC
    develop:
      watch:
        - action: sync
          path: ./src
          target: /app/src
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:17-alpine
    ports:
      - "5432:5432"
    environment:
      POSTGRES_DB: myapp_dev
      POSTGRES_USER: dev
      POSTGRES_PASSWORD: dev
    volumes:
      - postgres_dev:/var/lib/postgresql/data
      - ./docker/init-dev.sql:/docker-entrypoint-initdb.d/01-init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dev -d myapp_dev"]
      interval: 5s
      timeout: 3s
      retries: 10

volumes:
  postgres_dev:
```

### Production

Production Compose configuration uses pre-built images (never `build:`), explicit resource limits, and read-only filesystems. Note: Compose is only appropriate for production on single-host deployments (small internal tools, personal projects). For anything requiring HA, use a proper orchestrator.

```yaml
services:
  app:
    image: registry.example.com/myapp:1.2.3@sha256:abc123...
    restart: always
    read_only: true
    tmpfs:
      - /tmp
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 1G
        reservations:
          cpus: "0.5"
          memory: 512M
    environment:
      SPRING_PROFILES_ACTIVE: production
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080/actuator/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 60s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  db:
    image: postgres:17-alpine@sha256:def456...
    restart: always
    shm_size: 256mb
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 2G
    volumes:
      - postgres_prod:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U myapp"]
      interval: 30s
      timeout: 5s
      retries: 3

volumes:
  postgres_prod:
    driver: local
```

## Performance

**Startup performance:** Use `depends_on` with `condition: service_healthy` to prevent cascading startup failures. Without health checks, application containers start before databases are ready, causing connection errors, crash loops, and slow effective startup times. The `start_period` parameter on health checks gives slow-starting services (Elasticsearch, Kafka) grace time before the health check begins counting failures.

**Build performance:** Use BuildKit (`DOCKER_BUILDKIT=1` or Docker 23.0+ default) for parallel multi-stage builds. Use `build.cache_from` to leverage registry-based caches in CI. Use `docker compose build --parallel` to build multiple service images concurrently.

**Volume performance on MacOS:** Docker Desktop on MacOS runs containers in a Linux VM, making bind mounts significantly slower than native filesystem access. For large `node_modules` directories or Go module caches, use named volumes instead of bind mounts for dependency directories. Alternatively, use Compose Watch (`develop.watch`) which uses efficient rsync-like file synchronization instead of filesystem mounts.

**Resource limits:** Always set `deploy.resources.limits` in production Compose files. Without limits, a single runaway container can consume all host memory and trigger the OOM killer, taking down unrelated services.

## Security

**Secrets management:** Compose supports `secrets` as a top-level key, reading from files or environment variables. In production, use Docker secrets (file-based) rather than environment variables — environment variables are visible via `docker inspect` and often logged by application frameworks.

```yaml
services:
  app:
    image: myapp:latest
    secrets:
      - db_password
      - api_key
    environment:
      DB_PASSWORD_FILE: /run/secrets/db_password

secrets:
  db_password:
    file: ./secrets/db_password.txt
  api_key:
    environment: API_KEY
```

**Network isolation:** By default, all services in a Compose project share a single network. Create explicit networks to isolate service groups — for example, the application can reach the database, but the database should not be accessible from the frontend build container.

```yaml
services:
  app:
    networks:
      - frontend
      - backend

  db:
    networks:
      - backend

  nginx:
    networks:
      - frontend

networks:
  frontend:
  backend:
```

**Read-only filesystem and privilege dropping:** Use `read_only: true`, `security_opt: [no-new-privileges:true]`, and `tmpfs` mounts for temporary directories. This prevents attackers who gain container access from writing malicious binaries or escalating privileges.

## Testing

**CI integration testing with Compose:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Start infrastructure
docker compose -f compose.yml -f compose.ci.yml up -d db redis

# Wait for health
docker compose -f compose.yml -f compose.ci.yml exec db \
  pg_isready -U test -d testdb --timeout=30

# Run tests against containerized infrastructure
./gradlew integrationTest \
  -Dspring.datasource.url=jdbc:postgresql://localhost:5432/testdb

# Cleanup
docker compose -f compose.yml -f compose.ci.yml down -v
```

**Compose config validation:**
```bash
# Validate compose file syntax
docker compose config --quiet

# Dry-run — show resolved configuration
docker compose config

# Check for deprecated features
docker compose config --no-interpolate 2>&1 | grep -i "warn"
```

**Container health verification:**
```bash
# Check all service health statuses
docker compose ps --format json | jq '.[] | {Name, Health}'

# Wait for all services to be healthy
docker compose up -d --wait
```

## Dos

- Use `depends_on` with `condition: service_healthy` to ensure dependent services wait for actual readiness, not just container start.
- Include health checks for every service — both infrastructure (databases, caches) and application containers.
- Use profiles to group optional services (monitoring, debugging, seeding) that not every developer needs.
- Use named volumes for persistent data (database files) and anonymous volumes for ephemeral caches (`node_modules`).
- Use `.env` files for environment-specific configuration and commit a `.env.example` template with dummy values.
- Use `restart: unless-stopped` for development and `restart: always` for production single-host deployments.
- Use Compose Watch (`develop.watch`) for efficient hot-reload workflows, especially on MacOS where bind mount performance is poor.
- Use override files (`compose.override.yml`, `compose.ci.yml`) to separate development, CI, and production concerns.

## Don'ts

- Do not include the `version` key in Compose files — it is deprecated in Compose V2 and generates warnings.
- Do not use the standalone `docker-compose` binary (V1) — it is deprecated; use `docker compose` (V2 plugin).
- Do not hardcode secrets in `environment` blocks — use Docker secrets (`secrets:`) or external secret managers.
- Do not use Compose for production deployments that require high availability — it provides no multi-host scheduling or self-healing.
- Do not rely on `depends_on` without `condition: service_healthy` — container start order does not guarantee service readiness.
- Do not use bind mounts for dependency directories on MacOS (`node_modules`, `vendor`) — use named volumes or Compose Watch instead.
- Do not omit resource limits in production Compose files — runaway containers can trigger OOM kills on the host.
- Do not commit `.env` files with real secrets — commit `.env.example` with placeholder values and add `.env` to `.gitignore`.
