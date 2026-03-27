# FluxCD with FastAPI

> Extends `modules/container-orchestration/fluxcd.md` with FastAPI GitOps deployment patterns.
> Generic FluxCD conventions (GitRepository, Kustomization, HelmRelease) are NOT repeated here.

## Integration Setup

```yaml
# clusters/production/fastapi-app.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: fastapi-app
  namespace: production
spec:
  interval: 5m
  chart:
    spec:
      chart: ./helm/fastapi-app
      sourceRef:
        kind: GitRepository
        name: fastapi-app
        namespace: flux-system
  values:
    replicaCount: 3
    image:
      repository: registry.example.com/fastapi-app
      tag: latest
    uvicorn:
      workers: 4
```

## Framework-Specific Patterns

### Image Automation

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: fastapi-app
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: fastapi-app
  policy:
    semver:
      range: ">=1.0.0"
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: fastapi-app
  namespace: flux-system
spec:
  image: registry.example.com/fastapi-app
  interval: 1m
```

### Environment-Specific Overlays

```
clusters/
  dev/
    fastapi-app.yaml        # replicas: 1, workers: 1
  staging/
    fastapi-app.yaml        # replicas: 2, workers: 2
  production/
    fastapi-app.yaml        # replicas: 3, workers: 4
```

Each environment patches the base HelmRelease with different replica counts and worker configurations.

### Alembic Migration via Helm Hook

The HelmRelease delegates migration to a Helm pre-upgrade hook job (same as defined in the Helm chart's `templates/migration-job.yaml`). FluxCD runs Helm hooks as part of the release lifecycle.

```yaml
spec:
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
    cleanupOnFail: true
```

### Health Assessment

```yaml
spec:
  timeout: 5m
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: fastapi-app
      namespace: production
```

FluxCD monitors the Deployment's rollout status. If pods fail readiness probes (FastAPI `/health` endpoint), the release is marked as failed and remediation triggers.

## Scaffolder Patterns

```yaml
patterns:
  helmrelease: "clusters/{env}/fastapi-app.yaml"
  image_policy: "clusters/flux-system/image-policies/fastapi-app.yaml"
```

## Additional Dos

- DO use FluxCD image automation for automatic image tag updates
- DO configure remediation with retries for transient deployment failures
- DO use health checks referencing the Deployment for rollout verification
- DO keep environment-specific values in per-cluster directories

## Additional Don'ts

- DON'T put secrets in GitRepository manifests -- use SOPS or Sealed Secrets
- DON'T skip `timeout` on HelmRelease -- stuck rollouts block the reconciliation loop
- DON'T disable remediation retries -- transient failures are common during rolling updates
