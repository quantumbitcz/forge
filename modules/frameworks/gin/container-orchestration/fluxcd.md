# FluxCD with Gin

> Extends `modules/container-orchestration/fluxcd.md` with Gin GitOps deployment patterns.
> Generic FluxCD conventions (GitRepository, Kustomization, HelmRelease) are NOT repeated here.

## Integration Setup

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: gin-app
  namespace: production
spec:
  interval: 5m
  chart:
    spec:
      chart: ./helm/gin-app
      sourceRef:
        kind: GitRepository
        name: gin-app
        namespace: flux-system
  values:
    replicaCount: 3
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
  timeout: 3m
```

## Scaffolder Patterns

```yaml
patterns:
  helmrelease: "clusters/{env}/gin-app.yaml"
```

## Additional Dos

- DO use shorter timeouts -- Go starts instantly
- DO configure remediation with retries
- DO use image automation for automatic updates

## Additional Don'ts

- DON'T put secrets in Git
- DON'T skip `timeout` on HelmRelease
