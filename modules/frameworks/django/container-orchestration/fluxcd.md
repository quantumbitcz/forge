# FluxCD with Django

> Extends `modules/container-orchestration/fluxcd.md` with Django GitOps deployment patterns.
> Generic FluxCD conventions (GitRepository, Kustomization, HelmRelease) are NOT repeated here.

## Integration Setup

```yaml
# clusters/production/django-app.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: django-app
  namespace: production
spec:
  interval: 5m
  chart:
    spec:
      chart: ./helm/django-app
      sourceRef:
        kind: GitRepository
        name: django-app
        namespace: flux-system
  values:
    replicaCount: 3
    image:
      repository: registry.example.com/django-app
      tag: latest
    django:
      settingsModule: config.settings.production
      gunicornWorkers: 4
```

## Framework-Specific Patterns

### Image Automation

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: django-app
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: django-app
  policy:
    semver:
      range: ">=1.0.0"
```

### Environment Overlays

```
clusters/
  dev/
    django-app.yaml        # settingsModule: config.settings.dev
  staging/
    django-app.yaml        # settingsModule: config.settings.staging
  production/
    django-app.yaml        # settingsModule: config.settings.production
```

### Migration via Helm Hook

The HelmRelease delegates Django migration to the Helm pre-upgrade hook job defined in the chart. FluxCD runs Helm hooks as part of the release lifecycle.

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

## Scaffolder Patterns

```yaml
patterns:
  helmrelease: "clusters/{env}/django-app.yaml"
  image_policy: "clusters/flux-system/image-policies/django-app.yaml"
```

## Additional Dos

- DO use FluxCD image automation for automatic image tag updates
- DO configure remediation with retries for transient deployment failures
- DO set `DJANGO_SETTINGS_MODULE` per environment via values overrides
- DO keep environment-specific values in per-cluster directories

## Additional Don'ts

- DON'T put secrets in GitRepository manifests -- use SOPS or Sealed Secrets
- DON'T skip `timeout` on HelmRelease -- stuck rollouts block reconciliation
- DON'T use the same `DJANGO_SETTINGS_MODULE` across all environments
