# FluxCD with Kubernetes

> Extends `modules/container-orchestration/fluxcd.md` with Kubernetes GitOps deployment patterns.
> Generic FluxCD conventions (source controllers, reconciliation, multi-tenancy) are NOT repeated here.

## Integration Setup

```yaml
# flux/clusters/production/app.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: infra-repo
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/org/infra-repo.git
  ref:
    branch: main
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: my-app
  namespace: production
spec:
  interval: 5m
  chart:
    spec:
      chart: charts/my-app
      sourceRef:
        kind: GitRepository
        name: infra-repo
        namespace: flux-system
  values:
    image:
      repository: ghcr.io/org/my-app
      tag: latest
  valuesFrom:
    - kind: ConfigMap
      name: app-values
      valuesKey: values-production.yaml
```

## Framework-Specific Patterns

### Image Automation

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: my-app
  namespace: flux-system
spec:
  image: ghcr.io/org/my-app
  interval: 1m
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: my-app
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: my-app
  policy:
    semver:
      range: ">=1.0.0"
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageUpdateAutomation
metadata:
  name: my-app
  namespace: flux-system
spec:
  interval: 1m
  sourceRef:
    kind: GitRepository
    name: infra-repo
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        name: flux
        email: flux@example.com
    push:
      branch: main
  update:
    path: ./charts/my-app
    strategy: Setters
```

Flux Image Automation watches registries, updates manifests in Git, and triggers reconciliation. It modifies the Git repo directly -- true GitOps.

### Multi-Environment Kustomization

```yaml
# flux/clusters/production/kustomization.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: my-app
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: infra-repo
  path: ./deploy/overlays/production
  prune: true
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: my-app
      namespace: production
  timeout: 5m
```

### SOPS Secret Decryption

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age-key
```

Flux integrates with SOPS for encrypting secrets in Git. Secrets are decrypted at apply time using a key stored in a Kubernetes Secret.

### Dependency Ordering

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: my-app
spec:
  dependsOn:
    - name: database
    - name: migrations
  interval: 5m
```

## Scaffolder Patterns

```yaml
patterns:
  git_repository: "flux/sources/git-repository.yaml"
  helm_release: "flux/releases/app.yaml"
  kustomization: "flux/clusters/{env}/kustomization.yaml"
```

## Additional Dos

- DO use Image Automation for automatic image tag updates in Git
- DO use `dependsOn` for ordered deployments (database before app)
- DO use SOPS for encrypted secrets in Git
- DO set `prune: true` for garbage collection of removed resources
- DO use `healthChecks` to validate deployment success

## Additional Don'ts

- DON'T enable `prune` without testing -- it deletes resources not in Git
- DON'T store unencrypted secrets in Git -- use SOPS or External Secrets
- DON'T set `interval` too low -- frequent reconciliation adds API server load
- DON'T skip `healthChecks` -- without them, Flux considers sync successful even if pods crash
