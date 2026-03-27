# ArgoCD with Kubernetes

> Extends `modules/container-orchestration/argocd.md` with Kubernetes GitOps deployment patterns.
> Generic ArgoCD conventions (Application CRD, sync policies, health checks) are NOT repeated here.

## Integration Setup

```yaml
# argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/infra-repo.git
    targetRevision: main
    path: charts/my-app
    helm:
      valueFiles:
        - values.yaml
        - values-production.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

## Framework-Specific Patterns

### Multi-Environment with ApplicationSet

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: my-app
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: dev
            namespace: dev
            values_file: values-dev.yaml
          - cluster: staging
            namespace: staging
            values_file: values-staging.yaml
          - cluster: production
            namespace: production
            values_file: values-production.yaml
  template:
    metadata:
      name: my-app-{{cluster}}
    spec:
      source:
        repoURL: https://github.com/org/infra-repo.git
        targetRevision: main
        path: charts/my-app
        helm:
          valueFiles:
            - values.yaml
            - "{{values_file}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{namespace}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### Image Updater Integration

```yaml
# annotations on the Application
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: app=ghcr.io/org/my-app
    argocd-image-updater.argoproj.io/app.update-strategy: latest
    argocd-image-updater.argoproj.io/app.helm.image-name: image.repository
    argocd-image-updater.argoproj.io/app.helm.image-tag: image.tag
```

ArgoCD Image Updater watches container registries and updates Helm values automatically when new images appear. This closes the GitOps loop: CI pushes images, ArgoCD deploys them.

### Sync Waves for Ordered Deployment

```yaml
# Database migration job runs before app deployment
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
  annotations:
    argocd.argoproj.io/sync-wave: "-1"  # runs before wave 0
    argocd.argoproj.io/hook: PreSync
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: ghcr.io/org/migrator:latest
          command: ["migrate", "up"]
      restartPolicy: Never
```

### Health Checks

```yaml
# Custom health check for CRDs
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  ignoreDifferences:
    - group: ""
      kind: ConfigMap
      jsonPointers:
        - /data/last-updated  # ignore dynamic fields
```

## Scaffolder Patterns

```yaml
patterns:
  application: "argocd/application.yaml"
  applicationset: "argocd/applicationset.yaml"
```

## Additional Dos

- DO use `automated` sync with `selfHeal: true` for continuous reconciliation
- DO use `ApplicationSet` for multi-environment deployments from a single template
- DO use sync waves for ordered deployments (migrations before app)
- DO use ArgoCD Image Updater for automated image promotion

## Additional Don'ts

- DON'T enable `automated.prune` without testing -- it deletes resources not in Git
- DON'T use `selfHeal` without understanding drift detection -- it reverts manual changes
- DON'T put secrets in Git-tracked value files -- use External Secrets Operator or Sealed Secrets
- DON'T skip `ignoreDifferences` for dynamically-updated fields -- they cause perpetual drift
