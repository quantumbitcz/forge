# Kubernetes / Helm / Docker Framework Conventions

> Infrastructure conventions for K8s-based projects. No language layer -- this module covers YAML/Helm manifests, Dockerfiles, and deployment patterns.

## Infrastructure as Code Principles

- **Declarative over imperative:** All infrastructure in version-controlled manifests. No ad-hoc `kubectl apply` from local machines.
- **Immutability:** Never mutate running containers in-place. All changes through manifest-to-deploy pipeline.
- **Reproducibility:** Any environment recreatable from repo contents + external secrets.
- **Least privilege:** Every component runs with minimum required permissions.

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
```

**Naming:** Chart name matches service. Template filenames match K8s resource kind.
**Values structure:** Group by concern. Never nest deeper than 3 levels.

## Kubernetes Security

### RBAC
- Dedicated ServiceAccount per workload (never use `default`)
- RoleBindings scoped to namespace -- ClusterRoleBindings only for cluster-wide operators
- Least privilege: only grant verbs actually needed

### Pod Security
- `runAsNonRoot: true` -- always
- `readOnlyRootFilesystem: true` -- unless writable tmp needed (use emptyDir)
- `allowPrivilegeEscalation: false` -- always
- `capabilities.drop: ["ALL"]` -- drop all, add back only what needed
- Never run privileged containers

### Network Policies
- Default-deny ingress per namespace, then whitelist
- Label-based selectors; never IP-based for intra-cluster
- Egress policies for sensitive namespaces

## Resource Management

Every container must declare requests and limits:
- Requests = scheduling guarantee. Limits = OOM/throttle ceiling.
- CPU limits optional if HPA configured. Memory limits mandatory.
- Use `LimitRange` and `ResourceQuota` at namespace level.

## Health Probes

Every deployment must define:
- **livenessProbe:** Detects deadlocks. Restart on failure. Path: `/healthz`
- **readinessProbe:** Gates traffic. Removed from Service endpoints on failure. Path: `/readyz`
- **startupProbe:** For slow-starting apps. `failureThreshold * periodSeconds > max startup time`

## GitOps Patterns

- Single source of truth: Git repo is desired state
- Pull-based deployment: ArgoCD / Flux watches repo
- Environment promotion: main -> staging (auto-sync) -> production (manual approval)
- Drift detection: manual changes auto-reverted

### Image Tags
- **Never use `:latest`** -- defeats reproducibility
- Use immutable tags: `:{semver}` or `:{git-sha}`
- Pin base images in Dockerfiles to a digest or specific version

## Docker Best Practices

- **Multi-stage builds:** Separate build and runtime stages
- **Non-root user:** Always add `USER` instruction before CMD/ENTRYPOINT
- **Minimal base images:** Prefer `-alpine` or distroless variants
- **Layer caching:** COPY dependency manifests first, then install, then source
- **COPY over ADD** -- ADD has implicit tar extraction
- **.dockerignore** -- exclude `.git`, `node_modules`, test files, IDE configs
- No secrets baked into images

## Secret Management

- **Never commit secrets** to Git
- Use External Secrets Operator or Sealed Secrets
- Reference secrets via `secretKeyRef` in env vars or mounted volumes
- Rotate secrets regularly; use short-lived tokens
- Mark secrets as `immutable: true`

## Docker Compose (Local Development)

- `depends_on` with `condition: service_healthy`
- Named volumes for persistent data
- Always pin image versions
- Use `.env` file for local secrets -- never commit

## Code Quality

- Helm charts: `helm lint` with zero warnings
- K8s manifests: `kube-linter lint` with default checks
- Dockerfiles: `hadolint` with no errors
- YAML: no tabs, 2-space indent, no trailing whitespace

## Observability

### Metrics
- Prometheus metrics on `/metrics` endpoint
- Monitor: request rate, error rate, latency (RED method)
- Alerts for: pod restart loops, OOM kills, PV >80% usage

### Logging
- Structured JSON logging -- parseable by Loki, ELK, CloudWatch
- Include: timestamp, level, service name, trace ID
- Log to stdout/stderr -- platform collects

### Tracing
- OpenTelemetry for distributed tracing
- Propagate trace context via HTTP headers

## TDD Flow (Infrastructure)

scaffold chart/manifest -> write helm test or dry-run assertion (RED) -> implement templates (GREEN) -> lint and refactor

## Dos and Don'ts

### Do
- Set resource requests AND limits for all containers
- Use `readinessProbe` and `livenessProbe` on all services
- Use `PodDisruptionBudget` for stateful and critical workloads
- Use `NetworkPolicy` for pod-to-pod communication control
- Pin image tags to SHA digests in production

### Don't
- Don't run containers as root
- Don't use `hostNetwork` or `hostPID` unless absolutely necessary
- Don't store secrets in ConfigMaps
- Don't set CPU limits too low -- causes throttling
- Don't use `kubectl apply` with stdin in CI -- use declarative YAML from git
