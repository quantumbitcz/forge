# Infra Testing Enhancement — Cross-Repo Full Stack Verification

> **Scope:** Extend `infra-deploy-verifier` with Tier 4 (contract testing with stubs) and Tier 5 (full stack integration with real service images). Add cross-repo image resolution, user-defined scenario tests, and layered health/smoke/scenario test execution. Part of v1.5.0.
>
> **Status:** Design approved
>
> **Dependencies:** Spec 2 (Neo4j Multi-Project Namespacing) — recommended for cross-repo service discovery via graph queries. No hard dependency.

---

## 1. Problem Statement

The current `infra-deploy-verifier` tests infrastructure manifests in isolation:

- Tier 1 validates syntax (helm lint, kubectl dry-run)
- Tier 2 validates containers (docker build, compose health)
- Tier 3 validates in an ephemeral cluster (kind/k3d) but only deploys the infra manifests themselves

The gap: infra that passes all three tiers can still fail when real services are deployed — routing rules point to wrong ports, environment variables are misconfigured for the actual service, network policies block legitimate traffic, DB migrations fail against real schemas. Cross-repo infra testing (deploying BE + FE + Infra together) is not supported.

## 2. Design Decisions

### Considered Alternatives

**Testing depth:**
1. Full stack only — rejected: expensive, slow, overkill for most changes
2. Contract testing only — rejected: misses integration issues that stubs can't catch
3. **Tiered: contract + full stack (chosen)** — Tier 4 gives fast confidence, Tier 5 gives full confidence

**Image sourcing:**
1. Always build fresh — rejected: slow, wastes time when CI has already built images
2. Registry-first, build fallback — rejected: not configurable enough for mixed scenarios
3. **Configurable per service with auto default (chosen)** — registry-first with build fallback, overridable per service

**Test scenarios:**
1. Health checks only — rejected: validates pods run but not that they work
2. Health + smoke — rejected: misses user-defined business-critical paths
3. **Health + smoke + user scenarios (chosen)** — layered within each tier, scenario tests opt-in via `tests/infra/`

### Justification

The tiered approach matches the existing infra testing philosophy: each tier adds confidence at the cost of time. Users control the trade-off via `max_verification_tier`. The `tests/infra/` convention mirrors how the test bootstrapper discovers tests — if the directory exists, run them; if not, skip silently.

## 3. Tier Structure

### Existing Tiers (unchanged)

| Tier | Name | Time | Requirements |
|------|------|------|-------------|
| 1 | Static validation | <10s | kubectl, helm |
| 2 | Container validation | <60s | docker |
| 3 | Isolated cluster | <5min | kind/k3d |

### New Tiers

| Tier | Name | Time | Requirements |
|------|------|------|-------------|
| 4 | Contract testing | <5min | kind/k3d, stub images |
| 5 | Full stack integration | <15min | kind/k3d, service images |

### Tier 4 — Contract Testing

Deploys infra manifests + lightweight stub containers that satisfy health checks and API contract schemas. Validates:
- Service discovery and DNS resolution between services
- Ingress/networking routing rules
- ConfigMap/Secret injection into pods
- Volume mounts and PVC binding
- Environment variable propagation

Stub containers are auto-generated: a minimal HTTP server that returns canned responses matching the API contract (from OpenAPI spec if available, or simple 200 OK health endpoint).

Stub generator modes:
- `auto` — use OpenAPI spec if found, else health-only stubs
- `openapi` — require OpenAPI spec, fail if not found
- `health-only` — minimal stubs that only respond to health endpoints

### Tier 5 — Full Stack Integration

Deploys infra manifests + real service images from all related repos. Validates:
- End-to-end connectivity (FE → BE → DB)
- DB migrations apply successfully
- Cross-service authentication works
- Actual API responses match expected schemas

### Test Layers Within Each Tier

Each tier (3-5) runs three test layers in order:

1. **Health** (mandatory) — pod readiness, service reachability
2. **Smoke** (default) — HTTP endpoint checks, basic connectivity
3. **Scenario** (opt-in) — user scripts from `tests/infra/`

## 4. Configuration

### `forge.local.md` Extension

```yaml
infra:
  max_verification_tier: 3        # 1-5, default 3
  cluster_tool: kind               # kind | k3d
  compose_file: deploy/docker-compose.yml
  helm_chart: deploy/helm/myapp
  scenario_timeout_seconds: 60     # per-script timeout, default 60

  # Tier 4 settings
  contract_testing:
    stub_generator: auto           # auto | openapi | health-only
    openapi_spec: docs/api-spec.yaml  # optional, for contract stubs

  # Tier 5 settings
  stack_testing:
    timeout_minutes: 15            # max time for full stack test
    services:
      wellplanned-be:
        image_source: auto         # registry | build | auto
        registry: ghcr.io/quantumbitcz/wellplanned-be
        tag: latest                # or branch name, SHA
        dockerfile: Dockerfile     # relative to project root
        health_endpoint: /actuator/health
      wellplanned-fe:
        image_source: auto
        registry: ghcr.io/quantumbitcz/wellplanned-fe
        tag: latest
        dockerfile: Dockerfile
        health_endpoint: /
      postgres:
        image_source: registry
        registry: postgres
        tag: "16-alpine"
        health_endpoint: null      # uses TCP check instead
```

Services not listed in `stack_testing.services` but referenced in Helm charts/compose files are treated as `image_source: registry` with their existing image reference.

### Scenario Test Convention

User-defined tests live in `tests/infra/`:

```
tests/infra/
  smoke/                    # runs at smoke layer (Tiers 3-5)
    health.sh               # basic health checks
    connectivity.sh         # cross-service connectivity
  contract/                 # runs at Tier 4-5
    api-contract.sh         # validate API responses match schema
    dns-resolution.sh       # service discovery checks
  integration/              # runs at Tier 5 only
    e2e-flow.sh            # full user flow
    migration-verify.sh    # DB migration validation
```

Each script:
- Receives `CLUSTER_NAME`, `KUBECONFIG`, `NAMESPACE` as environment variables
- Exit code 0 = pass, non-zero = fail
- Stdout/stderr captured in stage notes
- Timeout: `infra.scenario_timeout_seconds` (default 60s)

## 5. Cross-Repo Image Resolution

### Resolution Algorithm

When Tier 5 needs a service image, the `infra-deploy-verifier` resolves it per the `image_source` config:

**`registry` mode:**
1. Pull `{registry}:{tag}` directly
2. If pull fails → CRITICAL finding, skip this service

**`build` mode:**
1. Locate related project via `related_projects` in `forge.local.md`
2. Build image: `docker build -t {service_name}:forge-test -f {dockerfile} {project_root}`
3. Load into cluster: `kind load docker-image {service_name}:forge-test`
4. If build fails → CRITICAL finding, skip this service

**`auto` mode (default):**
1. Try `docker pull {registry}:{tag}`
2. If pull succeeds and image is <24h old → use it
3. If pull fails or image is stale → fall back to `build` mode
4. If both fail → WARNING finding, deploy with stub instead (graceful degradation to Tier 4 behavior for this service)

### Image Staleness Check

For `auto` mode, staleness is determined by:
```bash
docker inspect --format='{{.Created}}' {registry}:{tag}
```
If the image creation timestamp is >24h old and the related project has commits newer than the image → considered stale, trigger build.

### Graph Integration

When Neo4j is available, the `infra-deploy-verifier` queries the graph to discover service relationships:

```cypher
MATCH (d:ProjectDependency {project_id: $infra_project_id})
WHERE d.name CONTAINS $service_name
RETURN d.name, d.version
```

Cross-references with related project configs:
```cypher
MATCH (pc:ProjectConfig)
WHERE pc.project_id IN $related_project_ids
RETURN pc.project_id, pc.language, pc.component
```

This helps auto-detect which services need to be deployed even when not explicitly listed in `stack_testing.services`. Without Neo4j, the verifier relies solely on explicit configuration.

## 6. Cluster Lifecycle

### Ephemeral Cluster Per Tier

Each tier creates its own cluster:

```
Tier 3: kind create cluster --name forge-verify-3
Tier 4: kind create cluster --name forge-verify-4
Tier 5: kind create cluster --name forge-verify-5
```

Separate clusters prevent state leakage between tiers. Cleanup: clusters are always deleted on completion, even on failure (ensured by `finally` block in verifier).

### Tier 5 Deployment Order

Services deployed in dependency order (from Helm chart dependencies or explicit config):

1. **Infrastructure services** — databases, message brokers, caches (postgres, redis, rabbitmq)
2. **Backend services** — API servers, workers
3. **Frontend services** — web servers
4. **Ingress/networking** — ingress controller, network policies

Each service waits for readiness before the next deploys:
```bash
kubectl wait --for=condition=ready pod -l app={service} --timeout=120s
```

### Test Execution Within Cluster

After all services are ready, tests run in layer order:

```
1. Health checks (built-in)
   - kubectl get pods --field-selector=status.phase!=Running → expect empty
   - For each service: curl {health_endpoint} → expect 2xx

2. Smoke tests (built-in + tests/infra/smoke/)
   - Cross-service connectivity: curl from pod A to service B
   - Ingress reachability: curl via ingress hostname
   - User scripts from tests/infra/smoke/

3. Scenario tests (tests/infra/contract/ for Tier 4, tests/infra/integration/ for Tier 5)
   - Scripts receive CLUSTER_NAME, KUBECONFIG, NAMESPACE env vars
   - Per-script timeout from config
   - Results aggregated into findings
```

### Findings Format

| Code | Severity | Trigger |
|------|----------|---------|
| `INFRA-HEALTH` | CRITICAL | Pod/service health check failure |
| `INFRA-SMOKE` | WARNING | Smoke test failure |
| `INFRA-CONTRACT` | CRITICAL | Contract schema/routing validation failure |
| `INFRA-E2E` | CRITICAL | Full stack integration test failure |
| `INFRA-IMAGE` | WARNING (`auto` fallback) / CRITICAL (explicit `registry`/`build`) | Image resolution failure |

## 7. Impact Analysis

### 7.1 Files Modified

| File | Change |
|------|--------|
| `agents/infra-deploy-verifier.md` | Add Tiers 4-5, image resolution, scenario test runner, new findings codes |
| `modules/frameworks/k8s/conventions.md` | Document `tests/infra/` convention, script requirements |
| `shared/scoring.md` | Add `INFRA-HEALTH`, `INFRA-SMOKE`, `INFRA-CONTRACT`, `INFRA-E2E`, `INFRA-IMAGE` codes |
| `shared/graph/query-patterns.md` | Add pattern 20 for cross-repo service dependency discovery |
| `CLAUDE.md` | Update infra section with Tiers 4-5, config, convention, findings codes |

### 7.2 Files NOT Modified

- `agents/infra-deploy-reviewer.md` — reviews manifests statically, unaffected by runtime tiers
- Other agents — no infra testing awareness needed
- `shared/state-schema.md` — no new state fields (tier results go into stage notes)
- Check engine / hooks — no impact
- Module files (except k8s) — no impact

### 7.3 Graceful Degradation

Consistent with existing infra testing philosophy:
- Missing kind/k3d → Tiers 3-5 skipped, INFO note
- Image pull fails in `auto` mode → fallback to build, then fallback to stub
- Scenario test directory missing → layer skipped silently
- Tier 5 timeout → cluster torn down, WARNING finding, pipeline continues
- Neo4j unavailable → service discovery falls back to explicit config only

### 7.4 Backwards Compatibility

None needed. Default `max_verification_tier: 3` means existing projects see no change. Users opt in to Tiers 4-5 by increasing the value. The `tests/infra/` directory is purely opt-in — no scaffolding created unless user adds it.
