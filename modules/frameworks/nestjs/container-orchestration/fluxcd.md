# FluxCD with NestJS

> Extends `modules/container-orchestration/fluxcd.md` with NestJS GitOps deployment patterns.
> Generic FluxCD conventions (GitRepository, Kustomization, HelmRelease) are NOT repeated here.

## Integration Setup

```yaml
# clusters/production/nestjs-app.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nestjs-app
  namespace: production
spec:
  interval: 5m
  chart:
    spec:
      chart: ./helm/nestjs-app
      sourceRef:
        kind: GitRepository
        name: nestjs-app
        namespace: flux-system
  values:
    replicaCount: 3
    image:
      repository: registry.example.com/nestjs-app
      tag: latest
    swagger:
      enabled: "false"
```

## Framework-Specific Patterns

### Image Automation

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: nestjs-app
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: nestjs-app
  policy:
    semver:
      range: ">=1.0.0"
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
  helmrelease: "clusters/{env}/nestjs-app.yaml"
```

## Additional Dos

- DO use FluxCD image automation for automatic tag updates
- DO configure remediation with retries
- DO disable Swagger in production values
- DO keep per-environment values in cluster directories

## Additional Don'ts

- DON'T put secrets in Git -- use SOPS or Sealed Secrets
- DON'T skip `timeout` on HelmRelease
- DON'T enable Swagger UI in production without auth
