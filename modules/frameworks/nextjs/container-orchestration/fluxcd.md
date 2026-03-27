# FluxCD with Next.js

> Extends `modules/container-orchestration/fluxcd.md` with Next.js GitOps deployment patterns.
> Generic FluxCD conventions (GitRepository, Kustomization, HelmRelease) are NOT repeated here.

## Integration Setup

```yaml
# clusters/production/nextjs-app.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nextjs-app
  namespace: production
spec:
  interval: 5m
  chart:
    spec:
      chart: ./helm/nextjs-app
      sourceRef:
        kind: GitRepository
        name: nextjs-app
        namespace: flux-system
  values:
    replicaCount: 3
    image:
      repository: registry.example.com/nextjs-app
      tag: latest
    isr:
      enabled: true
```

## Framework-Specific Patterns

### Image Automation

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: nextjs-app
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: nextjs-app
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
  helmrelease: "clusters/{env}/nextjs-app.yaml"
```

## Additional Dos

- DO use FluxCD image automation for automatic tag updates
- DO configure ISR cache PVC in HelmRelease values
- DO configure remediation with retries
- DO keep per-environment values in cluster directories

## Additional Don'ts

- DON'T put secrets in Git -- use SOPS or Sealed Secrets
- DON'T skip `timeout` on HelmRelease
- DON'T embed `NEXT_PUBLIC_*` build-time vars in the HelmRelease
