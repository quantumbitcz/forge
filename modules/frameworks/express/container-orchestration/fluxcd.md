# FluxCD with Express

> Extends `modules/container-orchestration/fluxcd.md` with Express GitOps deployment patterns.
> Generic FluxCD conventions (GitRepository, Kustomization, HelmRelease) are NOT repeated here.

## Integration Setup

```yaml
# clusters/production/express-app.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: express-app
  namespace: production
spec:
  interval: 5m
  chart:
    spec:
      chart: ./helm/express-app
      sourceRef:
        kind: GitRepository
        name: express-app
        namespace: flux-system
  values:
    replicaCount: 3
    image:
      repository: registry.example.com/express-app
      tag: latest
```

## Framework-Specific Patterns

### Image Automation

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: express-app
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: express-app
  policy:
    semver:
      range: ">=1.0.0"
```

### Environment Overlays

Each environment sets `NODE_ENV` and replica count via the HelmRelease values.

### Remediation

```yaml
spec:
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
    cleanupOnFail: true
  timeout: 5m
```

## Scaffolder Patterns

```yaml
patterns:
  helmrelease: "clusters/{env}/express-app.yaml"
```

## Additional Dos

- DO use FluxCD image automation for automatic tag updates
- DO configure remediation with retries for transient failures
- DO set `NODE_ENV=production` in the HelmRelease values
- DO keep environment-specific values in per-cluster directories

## Additional Don'ts

- DON'T put secrets in GitRepository manifests -- use SOPS or Sealed Secrets
- DON'T skip `timeout` on HelmRelease
- DON'T disable remediation retries
