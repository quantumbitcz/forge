# Infrastructure (K8s / Docker / Helm) Agent Conventions Reference

> Full details in project CLAUDE.md. This is a curated subset for agent consumption.

## Infrastructure as Code Principles

- **Declarative over imperative:** All infrastructure defined in version-controlled manifests (Helm charts, K8s YAML, Dockerfiles, Compose files). No ad-hoc `kubectl apply` from local machines.
- **Immutability:** Never mutate running containers or deployments in-place. All changes go through the manifest-to-deploy pipeline.
- **Reproducibility:** Any environment can be recreated from scratch using only the repo contents and external secrets.
- **Least privilege:** Every component runs with the minimum permissions required.

## Helm Chart Structure

```
charts/{service-name}/
  Chart.yaml              # name, version, appVersion, dependencies
  values.yaml             # default values (no secrets!)
  values-{env}.yaml       # environment-specific overrides
  templates/
    _helpers.tpl           # reusable named templates
    deployment.yaml
    service.yaml
    ingress.yaml
    configmap.yaml
    hpa.yaml
    networkpolicy.yaml
    serviceaccount.yaml
    NOTES.txt
  tests/
    test-connection.yaml
```

**Naming:** Chart name matches the service/application name. Template filenames match the K8s resource kind in lowercase.

**Values structure:** Group by concern (image, resources, service, ingress, autoscaling, security). Never nest deeper than 3 levels.

## Kubernetes Security

### RBAC
- Every workload gets a dedicated ServiceAccount (never use `default`).
- RoleBindings scoped to namespace — ClusterRoleBindings only for cluster-wide operators.
- Principle of least privilege: only grant verbs actually needed (e.g., `get`, `list`, `watch` — not `*`).

### Pod Security
- `runAsNonRoot: true` — always.
- `readOnlyRootFilesystem: true` — unless the app requires writable tmp (use an emptyDir volume for `/tmp`).
- `allowPrivilegeEscalation: false` — always.
- `capabilities.drop: ["ALL"]` — drop all, then add back only what is needed (rare).
- Never run privileged containers (`privileged: false`).

### Network Policies
- Default-deny ingress per namespace, then whitelist required traffic.
- Label-based selectors; never use IP-based rules for intra-cluster traffic.
- Egress policies for sensitive namespaces (databases, payment services).

## Resource Management

Every container must declare:
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

- Requests = scheduling guarantee. Limits = OOM/throttle ceiling.
- CPU limits are optional if HPA is configured (prefer throttling over eviction).
- Memory limits are mandatory — OOMKilled pods destabilize nodes.
- Use `LimitRange` and `ResourceQuota` at the namespace level as guardrails.

## Health Probes

Every deployment must define:
- **livenessProbe:** Detects deadlocks. Restart the pod if it fails. Path: `/healthz` or TCP check.
- **readinessProbe:** Gates traffic. Pod removed from Service endpoints if it fails. Path: `/readyz` or application-specific.
- **startupProbe:** For slow-starting apps. Disables liveness/readiness until the app is ready. Use `failureThreshold * periodSeconds > max startup time`.

Probe configuration:
- `initialDelaySeconds`: match expected startup time.
- `periodSeconds`: 10s default, 5s for critical services.
- `failureThreshold`: 3 for liveness (avoid flapping), 1 for readiness (fast failover).

## GitOps Patterns

- **Single source of truth:** The Git repo is the desired state. The cluster converges to match.
- **Pull-based deployment:** ArgoCD / Flux watches the repo — no `kubectl apply` in CI.
- **Environment promotion:** `main` -> staging (auto-sync) -> production (manual approval or PR-based).
- **Drift detection:** ArgoCD sync status monitored; manual changes are auto-reverted.

### Image Tags
- **Never use `:latest`** — it defeats reproducibility and rollback.
- Use immutable tags: `:{semver}` or `:{git-sha}` or `:{semver}-{git-sha-short}`.
- Pin base images in Dockerfiles to a digest or specific version.

## Docker Best Practices

### Multi-Stage Builds
```dockerfile
# Build stage
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --ignore-scripts
COPY . .
RUN npm run build

# Runtime stage
FROM node:22-alpine AS runtime
RUN addgroup -g 1001 appgroup && adduser -u 1001 -G appgroup -D appuser
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
USER appuser
EXPOSE 3000
CMD ["node", "dist/main.js"]
```

- **Separate build and runtime stages** — build tools never ship to production.
- **Non-root user** — always add a `USER` instruction before `CMD`/`ENTRYPOINT`.
- **Minimal base images** — prefer `-alpine` or distroless variants.
- **Layer caching** — COPY dependency manifests first, then `RUN install`, then COPY source.
- **COPY over ADD** — ADD has implicit tar extraction and URL fetch; use COPY for clarity.
- **`--no-install-recommends`** for apt-get — reduces image size and attack surface.
- **.dockerignore** — exclude `.git`, `node_modules`, test files, docs, IDE configs.

### Image Hygiene
- No secrets baked into images (no `ENV SECRET=...`, no `COPY .env`).
- Pin package versions in `RUN` instructions where practical.
- Use `HEALTHCHECK` instruction for standalone containers (not needed when K8s probes are configured).

## Secret Management

- **Never commit secrets** to Git — not in `values.yaml`, not in ConfigMaps, not in Dockerfiles.
- Use **External Secrets Operator** or **Sealed Secrets** to sync secrets from a vault (e.g., AWS Secrets Manager, HashiCorp Vault).
- Reference secrets in pods via `secretKeyRef` in env vars or mounted volumes.
- Rotate secrets regularly; use short-lived tokens where possible.
- Mark secrets as `immutable: true` in K8s Secret manifests to prevent accidental mutation.

## Docker Compose (Local Development)

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: runtime
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgresql://user:pass@db:5432/app
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/healthz"]
      interval: 10s
      timeout: 5s
      retries: 3

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  db-data:
```

- `depends_on` with `condition: service_healthy` — not just `depends_on: [db]`.
- Named volumes for persistent data.
- Always pin image versions (no `:latest`).
- Use `.env` file for local secrets — never commit it (add to `.gitignore`).

## Database Migrations

- Migrations are versioned, monotonically increasing, and immutable once applied.
- Use a dedicated migration tool (Flyway, Liquibase, golang-migrate, Alembic).
- Naming: `V{NNN}__{description}.sql` (Flyway) or `{timestamp}_{description}.sql`.
- Never modify an applied migration — create a new one instead.
- Migrations run before application startup (init container or migration job).

## Code Quality

- Helm charts: `helm lint` must pass with zero warnings.
- K8s manifests: `kube-linter lint` with default checks enabled.
- Dockerfiles: `hadolint` with no errors.
- YAML: no tabs, 2-space indent, no trailing whitespace.
- Line length: max 200 characters (YAML is naturally verbose).

## TDD Flow (Infrastructure)

scaffold chart/manifest -> write helm test or dry-run assertion (RED) -> implement templates (GREEN) -> lint and refactor

## Boy Scout Rule

Improve touched manifests if: safe, small (<10 lines), local (same chart/file), convention-aligned.
NOT in scope: refactoring unrelated charts, changing deployed APIs, modifying production values.
