# ArgoCD with FastAPI

> Extends `modules/container-orchestration/argocd.md` with FastAPI GitOps deployment patterns.
> Generic ArgoCD conventions (Application CRDs, sync policies, project scoping) are NOT repeated here.

## Integration Setup

```yaml
# argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fastapi-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/fastapi-app-deploy
    targetRevision: main
    path: helm/fastapi-app
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
```

## Framework-Specific Patterns

### Multi-Environment with ApplicationSet

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: fastapi-app
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: dev
            namespace: dev
            replicas: "1"
          - env: staging
            namespace: staging
            replicas: "2"
          - env: production
            namespace: production
            replicas: "3"
  template:
    metadata:
      name: "fastapi-app-{{env}}"
    spec:
      project: default
      source:
        repoURL: https://github.com/org/fastapi-app-deploy
        targetRevision: main
        path: helm/fastapi-app
        helm:
          valueFiles:
            - values.yaml
            - "values-{{env}}.yaml"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{namespace}}"
```

### Alembic Migration as PreSync Hook

```yaml
# templates/migration-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          command: ["alembic", "upgrade", "head"]
          envFrom:
            - secretRef:
                name: {{ .Release.Name }}-db
      restartPolicy: Never
  backoffLimit: 3
```

ArgoCD runs the migration job before deploying the new application version. The `BeforeHookCreation` policy cleans up the previous job.

### Image Update Automation

```yaml
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: app=registry.example.com/fastapi-app
    argocd-image-updater.argoproj.io/app.update-strategy: semver
    argocd-image-updater.argoproj.io/app.helm.image-name: image.repository
    argocd-image-updater.argoproj.io/app.helm.image-tag: image.tag
```

## Scaffolder Patterns

```yaml
patterns:
  application: "argocd/application.yaml"
  applicationset: "argocd/applicationset.yaml"
  values_env: "helm/{chart-name}/values-{env}.yaml"
```

## Additional Dos

- DO use ApplicationSet for multi-environment FastAPI deployments
- DO run Alembic migrations as ArgoCD PreSync hooks
- DO use ArgoCD Image Updater for automated image promotion
- DO configure `selfHeal: true` to revert manual Kubernetes changes

## Additional Don'ts

- DON'T put database credentials in the Git deploy repository -- use Sealed Secrets or External Secrets
- DON'T auto-sync production without a manual approval gate
- DON'T skip the migration PreSync hook -- schema drift causes application errors
