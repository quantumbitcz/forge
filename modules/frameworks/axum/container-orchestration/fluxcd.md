# FluxCD with Axum

> Extends `modules/container-orchestration/fluxcd.md` with Axum GitOps deployment patterns.
> Generic FluxCD conventions (GitRepository, Kustomization, HelmRelease) are NOT repeated here.

## Integration Setup

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: axum-app
  namespace: production
spec:
  interval: 5m
  chart:
    spec:
      chart: ./helm/axum-app
      sourceRef:
        kind: GitRepository
        name: axum-app
        namespace: flux-system
  values:
    replicaCount: 3
    image:
      repository: registry.example.com/axum-app
      tag: latest
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
  timeout: 3m
```

Axum deploys fast due to instant startup. Timeout can be shorter than JVM-based frameworks.

## Scaffolder Patterns

```yaml
patterns:
  helmrelease: "clusters/{env}/axum-app.yaml"
```

## Additional Dos

- DO use shorter timeouts -- Rust binaries start instantly
- DO configure remediation with retries
- DO use image automation for automatic tag updates

## Additional Don'ts

- DON'T put secrets in Git -- use SOPS or Sealed Secrets
- DON'T skip `timeout` on HelmRelease
