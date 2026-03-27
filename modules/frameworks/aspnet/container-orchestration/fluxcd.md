# FluxCD with ASP.NET

> Extends `modules/container-orchestration/fluxcd.md` with ASP.NET Core GitOps deployment patterns.
> Generic FluxCD conventions (GitRepository, Kustomization, HelmRelease) are NOT repeated here.

## Integration Setup

```yaml
# clusters/production/aspnet-app.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: aspnet-app
  namespace: production
spec:
  interval: 5m
  chart:
    spec:
      chart: ./helm/aspnet-app
      sourceRef:
        kind: GitRepository
        name: aspnet-app
        namespace: flux-system
  values:
    replicaCount: 3
    aspnet:
      environment: Production
```

## Framework-Specific Patterns

### Environment Overlays

```
clusters/
  dev/
    aspnet-app.yaml        # environment: Development
  staging/
    aspnet-app.yaml        # environment: Staging
  production/
    aspnet-app.yaml        # environment: Production
```

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
  helmrelease: "clusters/{env}/aspnet-app.yaml"
```

## Additional Dos

- DO use FluxCD image automation for automatic tag updates
- DO set `ASPNETCORE_ENVIRONMENT` per cluster
- DO configure remediation with retries
- DO keep per-environment values in cluster directories

## Additional Don'ts

- DON'T put secrets in Git -- use SOPS or Sealed Secrets
- DON'T skip `timeout` on HelmRelease
- DON'T use `Development` environment in production clusters
