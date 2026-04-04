# Infra Testing Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `infra-deploy-verifier` with Tier 4 (contract testing with stubs) and Tier 5 (full stack integration with real service images). Add cross-repo image resolution and user-defined scenario tests.

**Architecture:** Existing 3-tier structure extended to 5 tiers. Tier 4 deploys infra + stub containers. Tier 5 deploys infra + real service images (registry or local build). User scenario tests in `tests/infra/`. Each tier creates its own ephemeral kind/k3d cluster.

**Tech Stack:** Markdown (agent definition), Bash (cluster scripts), Cypher (service discovery), Bats (tests)

**Spec:** `docs/superpowers/specs/2026-04-04-infra-testing-enhancement-design.md`

---

### Task 1: Add new findings codes to scoring

**Files:**
- Modify: `shared/scoring.md`

- [ ] **Step 1: Add INFRA-* findings codes**

In the category table, add:

```markdown
| `INFRA-HEALTH` | Pod/service health check failure | CRITICAL |
| `INFRA-SMOKE` | Smoke test failure | WARNING |
| `INFRA-CONTRACT` | Contract schema/routing validation failure | CRITICAL |
| `INFRA-E2E` | Full stack integration test failure | CRITICAL |
| `INFRA-IMAGE` | Image resolution failure | WARNING (auto fallback) / CRITICAL (explicit) |
```

Add to the wildcard prefix list: `INFRA-*` should already be there — verify it covers these new codes.

- [ ] **Step 2: Commit**

```bash
git add shared/scoring.md
git commit -m "feat: add INFRA-HEALTH, INFRA-SMOKE, INFRA-CONTRACT, INFRA-E2E, INFRA-IMAGE codes"
```

---

### Task 2: Write contract tests for Tier 4-5

**Files:**
- Create: `tests/contract/infra-tiers.bats`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bats
# Contract tests: infra-deploy-verifier supports Tiers 4-5.

load '../helpers/test-helpers'

VERIFIER="$PLUGIN_ROOT/agents/infra-deploy-verifier.md"

# ---------------------------------------------------------------------------
# 1. Verifier documents Tier 4 (contract testing)
# ---------------------------------------------------------------------------
@test "infra-tiers: verifier documents Tier 4 contract testing" {
  grep -qi 'tier 4' "$VERIFIER"
  grep -qi 'contract' "$VERIFIER"
  grep -qi 'stub' "$VERIFIER"
}

# ---------------------------------------------------------------------------
# 2. Verifier documents Tier 5 (full stack integration)
# ---------------------------------------------------------------------------
@test "infra-tiers: verifier documents Tier 5 full stack integration" {
  grep -qi 'tier 5' "$VERIFIER"
  grep -qi 'full stack\|integration' "$VERIFIER"
  grep -qi 'image_source\|registry\|build' "$VERIFIER"
}

# ---------------------------------------------------------------------------
# 3. Verifier supports max_verification_tier up to 5
# ---------------------------------------------------------------------------
@test "infra-tiers: verifier supports max_verification_tier 5" {
  grep -q 'max_verification_tier' "$VERIFIER"
  # Should reference values 1-5 somewhere
  grep -qE '1.?-?.?5|[1-5]' "$VERIFIER"
}

# ---------------------------------------------------------------------------
# 4. Verifier documents test layers (health, smoke, scenario)
# ---------------------------------------------------------------------------
@test "infra-tiers: verifier documents health/smoke/scenario test layers" {
  grep -qi 'health' "$VERIFIER"
  grep -qi 'smoke' "$VERIFIER"
  grep -qi 'scenario\|tests/infra/' "$VERIFIER"
}

# ---------------------------------------------------------------------------
# 5. Verifier documents image resolution (registry/build/auto)
# ---------------------------------------------------------------------------
@test "infra-tiers: verifier documents image resolution modes" {
  grep -qi 'registry' "$VERIFIER"
  grep -qi 'build' "$VERIFIER"
  grep -qi 'auto' "$VERIFIER"
}

# ---------------------------------------------------------------------------
# 6. New findings codes in scoring.md
# ---------------------------------------------------------------------------
@test "infra-tiers: scoring.md includes INFRA-HEALTH code" {
  grep -q 'INFRA-HEALTH' "$PLUGIN_ROOT/shared/scoring.md"
}

@test "infra-tiers: scoring.md includes INFRA-CONTRACT code" {
  grep -q 'INFRA-CONTRACT' "$PLUGIN_ROOT/shared/scoring.md"
}

@test "infra-tiers: scoring.md includes INFRA-E2E code" {
  grep -q 'INFRA-E2E' "$PLUGIN_ROOT/shared/scoring.md"
}

@test "infra-tiers: scoring.md includes INFRA-IMAGE code" {
  grep -q 'INFRA-IMAGE' "$PLUGIN_ROOT/shared/scoring.md"
}

# ---------------------------------------------------------------------------
# 7. K8s conventions document tests/infra/ directory
# ---------------------------------------------------------------------------
@test "infra-tiers: k8s conventions document tests/infra/" {
  grep -q 'tests/infra/' "$PLUGIN_ROOT/modules/frameworks/k8s/conventions.md"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./tests/lib/bats-core/bin/bats tests/contract/infra-tiers.bats
```

Expected: FAIL — verifier doesn't have Tier 4-5 yet

- [ ] **Step 3: Commit**

```bash
git add tests/contract/infra-tiers.bats
git commit -m "test: add infra tiers 4-5 contract tests (RED)"
```

---

### Task 3: Update infra-deploy-verifier with Tier 4

**Files:**
- Modify: `agents/infra-deploy-verifier.md`

- [ ] **Step 1: Add Tier 4 section**

After the existing Tier 3 section, add:

```markdown
## Tier 4 — Contract Testing (<5min)

**Requires:** kind or k3d (same as Tier 3)
**Triggered when:** `infra.max_verification_tier >= 4`

### 4.1 Stub Generation

Generate lightweight stub containers for each service in the deployment:

**auto mode** (default):
1. Check for OpenAPI spec at `infra.contract_testing.openapi_spec` path
2. If found: generate stub that returns canned responses matching the spec
3. If not found: generate health-only stub (responds 200 on health endpoint)

**openapi mode:**
1. Require OpenAPI spec — emit INFRA-CONTRACT CRITICAL if not found
2. Parse spec and generate per-endpoint stubs

**health-only mode:**
1. Generate minimal HTTP server: responds 200 on `/health`, 404 on everything else

Stub container: `nginx:alpine` with a custom `default.conf` generated per service.

### 4.2 Deployment

1. Create cluster: `kind create cluster --name forge-verify-4`
2. Deploy infra manifests (Helm or raw K8s) into the cluster
3. Deploy stub containers for each service referenced in the manifests
4. Wait for all pods to be ready

### 4.3 Validation

Run test layers in order:

**Health:**
- All pods running: `kubectl get pods --field-selector=status.phase!=Running` → expect empty
- All services reachable: `kubectl get endpoints` → all have addresses

**Smoke:**
- Service discovery: `kubectl exec` into a pod, `nslookup {service-name}`
- Ingress routing: `curl` via ingress hostname (if ingress configured)
- ConfigMap/Secret injection: verify expected env vars are set in pods
- Volume mounts: verify expected volumes are mounted

**Scenario (if tests/infra/contract/ exists):**
- Run each script in `tests/infra/contract/`
- Pass `CLUSTER_NAME`, `KUBECONFIG`, `NAMESPACE` env vars
- Timeout: `infra.scenario_timeout_seconds` per script (default 60)

### 4.4 Cleanup

Always: `kind delete cluster --name forge-verify-4`

### 4.5 Findings

| Finding | Severity | Trigger |
|---------|----------|---------|
| INFRA-HEALTH | CRITICAL | Pod/service not ready after 120s |
| INFRA-SMOKE | WARNING | DNS/ingress/config check failed |
| INFRA-CONTRACT | CRITICAL | Contract validation script failed |
```

- [ ] **Step 2: Commit**

```bash
git add agents/infra-deploy-verifier.md
git commit -m "feat: add Tier 4 contract testing to infra-deploy-verifier"
```

---

### Task 4: Update infra-deploy-verifier with Tier 5

**Files:**
- Modify: `agents/infra-deploy-verifier.md`

- [ ] **Step 1: Add Tier 5 section**

After Tier 4, add:

```markdown
## Tier 5 — Full Stack Integration (<15min)

**Requires:** kind or k3d, Docker, service images
**Triggered when:** `infra.max_verification_tier >= 5`

### 5.1 Image Resolution

For each service in `infra.stack_testing.services`:

**registry mode:**
1. `docker pull {registry}:{tag}`
2. Fail → INFRA-IMAGE CRITICAL

**build mode:**
1. Locate project via `related_projects` in `forge.local.md`
2. `docker build -t {service_name}:forge-test -f {dockerfile} {project_root}`
3. `kind load docker-image {service_name}:forge-test --name forge-verify-5`
4. Fail → INFRA-IMAGE CRITICAL

**auto mode (default):**
1. Try `docker pull {registry}:{tag}`
2. Check staleness: `docker inspect --format='{{.Created}}' {registry}:{tag}`
3. If image <24h old → use it
4. If pull fails or stale → fall back to build mode
5. If both fail → INFRA-IMAGE WARNING, deploy stub instead (graceful degradation)

Services not listed in config but referenced in manifests → `image_source: registry` with their existing image reference.

### 5.2 Deployment Order

Deploy in dependency order:
1. **Infrastructure:** databases, message brokers, caches (wait for ready)
2. **Backend:** API servers, workers (wait for ready)
3. **Frontend:** web servers (wait for ready)
4. **Ingress:** ingress controller, network policies

Per-service readiness: `kubectl wait --for=condition=ready pod -l app={service} --timeout=120s`

Dependency order derived from Helm chart dependencies or `infra.stack_testing.services` ordering.

### 5.3 Cluster Setup

1. Create cluster: `kind create cluster --name forge-verify-5`
2. For each service with `build` or `auto` (built locally):
   `kind load docker-image {service_name}:forge-test --name forge-verify-5`
3. Deploy in dependency order (§5.2)
4. Wait for all pods ready

### 5.4 Validation

Run test layers:

**Health:**
- All pods running
- All health endpoints responding (using `health_endpoint` from config, TCP check if null)

**Smoke:**
- Cross-service connectivity: exec into backend pod, curl frontend; exec into frontend pod, curl backend
- Ingress end-to-end: external request → ingress → backend → response
- Database connectivity: backend can reach DB and run a simple query

**Scenario (if tests/infra/integration/ exists):**
- Run each script in `tests/infra/integration/`
- Same env vars as Tier 4
- Timeout: `infra.scenario_timeout_seconds` per script

### 5.5 Cleanup

Always: `kind delete cluster --name forge-verify-5`
Timeout: `infra.stack_testing.timeout_minutes` (default 15) — if exceeded, force cleanup + INFRA-E2E WARNING.

### 5.6 Findings

| Finding | Severity | Trigger |
|---------|----------|---------|
| INFRA-HEALTH | CRITICAL | Service health check failed |
| INFRA-SMOKE | WARNING | Cross-service connectivity failed |
| INFRA-E2E | CRITICAL | Integration test script failed |
| INFRA-IMAGE | WARNING/CRITICAL | Image resolution failed (see §5.1) |
```

- [ ] **Step 2: Commit**

```bash
git add agents/infra-deploy-verifier.md
git commit -m "feat: add Tier 5 full stack integration to infra-deploy-verifier"
```

---

### Task 5: Document tests/infra/ convention in k8s module

**Files:**
- Modify: `modules/frameworks/k8s/conventions.md`

- [ ] **Step 1: Add scenario test convention section**

```markdown
## Infrastructure Scenario Tests

User-defined tests for infra verification live in `tests/infra/`:

\```
tests/infra/
  smoke/                    # Runs at Tiers 3-5 (smoke layer)
    health.sh               # Basic health endpoint checks
    connectivity.sh         # Cross-service network connectivity
  contract/                 # Runs at Tiers 4-5 (contract layer)
    api-contract.sh         # API response schema validation
    dns-resolution.sh       # Service discovery checks
  integration/              # Runs at Tier 5 only (integration layer)
    e2e-flow.sh            # Full user flow end-to-end
    migration-verify.sh    # Database migration validation
\```

### Script Requirements

Each script:
- Must have `#!/usr/bin/env bash` shebang and be executable (`chmod +x`)
- Receives environment variables: `CLUSTER_NAME`, `KUBECONFIG`, `NAMESPACE`
- Exit code 0 = pass, non-zero = fail
- Stdout/stderr captured in stage notes
- Timeout: `infra.scenario_timeout_seconds` (default 60s)

### Dos
- Use `kubectl` and `curl` for all checks — they are available in the cluster context
- Check actual behavior, not just pod status (health endpoints, actual responses)
- Clean up any test data created during the test

### Don'ts
- Don't hardcode cluster names or namespaces — use env vars
- Don't assume specific node counts or resource sizes
- Don't leave port-forwards running — clean up in a trap
```

- [ ] **Step 2: Commit**

```bash
git add modules/frameworks/k8s/conventions.md
git commit -m "docs: add tests/infra/ convention to k8s module"
```

---

### Task 6: Add graph query pattern for service discovery

**Files:**
- Modify: `shared/graph/query-patterns.md`

- [ ] **Step 1: Add Pattern 20**

```markdown
### 20. Cross-Repo Service Discovery

**Used during:** VERIFY (Tier 5 image resolution)

Discovers related project services and their Docker/deployment configuration.

\```cypher
MATCH (pc:ProjectConfig)
WHERE pc.project_id IN $related_project_ids
OPTIONAL MATCH (dep:ProjectDependency {project_id: pc.project_id})-[:MAPS_TO]->(fw:Framework)
RETURN pc.project_id, pc.language, pc.component, collect(DISTINCT fw.name) AS frameworks
\```

**Parameters:**
- `$related_project_ids` — List of project identifiers from `related_projects` in `forge.local.md`.
```

- [ ] **Step 2: Commit**

```bash
git add shared/graph/query-patterns.md
git commit -m "feat: add cross-repo service discovery query pattern"
```

---

### Task 7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update infra testing section**

Replace the existing infra testing description:

```markdown
- **Infra testing (5 tiers):** Tier 1: static (helm lint, kubectl dry-run). Tier 2: container (docker build, compose health, trivy). Tier 3: isolated cluster (kind/k3d, helm install, pod readiness, smoke tests). Tier 4: contract testing (infra + stub containers, DNS/routing/config validation, `tests/infra/contract/`). Tier 5: full stack integration (infra + real service images from registry or local build, end-to-end connectivity, `tests/infra/integration/`). Default: Tier 3. Configure via `infra.max_verification_tier` (1-5). Image source per service: `registry | build | auto` (default `auto`). See `infra-deploy-verifier.md`.
```

- [ ] **Step 2: Add findings codes**

In the scoring section, add the 5 new INFRA codes to the description.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with infra Tiers 4-5"
```

---

### Task 8: Run full test suite and verify

- [ ] **Step 1: Run infra tier tests**

```bash
./tests/lib/bats-core/bin/bats tests/contract/infra-tiers.bats
```

Expected: All tests PASS

- [ ] **Step 2: Run full test suite**

```bash
./tests/run-all.sh
```

Expected: All tests PASS

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve test regressions from infra testing enhancement"
```
