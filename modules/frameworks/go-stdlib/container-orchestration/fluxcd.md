# FluxCD with Go stdlib

> Extends `modules/container-orchestration/fluxcd.md` with Go stdlib GitOps deployment patterns.
> Generic FluxCD conventions (GitRepository, Kustomization, HelmRelease) are NOT repeated here.

## Integration Setup

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: go-app
  namespace: production
spec:
  interval: 5m
  chart:
    spec:
      chart: ./helm/go-app
      sourceRef:
        kind: GitRepository
        name: go-app
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
  helmrelease: "clusters/{env}/go-app.yaml"
```

## Additional Dos

- DO use shorter timeouts -- Go starts instantly
- DO configure remediation with retries

## Additional Don'ts

- DON'T put secrets in Git
- DON'T skip `timeout`
