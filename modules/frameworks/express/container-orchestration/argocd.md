# ArgoCD with Express

> Extends `modules/container-orchestration/argocd.md` with Express GitOps deployment patterns.
> Generic ArgoCD conventions (Application CRDs, sync policies, project scoping) are NOT repeated here.

## Integration Setup

```yaml
# argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: express-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/express-app-deploy
    targetRevision: main
    path: helm/express-app
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

### Multi-Environment ApplicationSet

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: express-app
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: dev
            namespace: dev
          - env: staging
            namespace: staging
          - env: production
            namespace: production
  template:
    metadata:
      name: "express-app-{{env}}"
    spec:
      source:
        repoURL: https://github.com/org/express-app-deploy
        targetRevision: main
        path: helm/express-app
        helm:
          valueFiles:
            - values.yaml
            - "values-{{env}}.yaml"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{namespace}}"
```

### Database Migration as PreSync Hook

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
          command: ["npx", "prisma", "migrate", "deploy"]
          envFrom:
            - secretRef:
                name: {{ .Release.Name }}-db
      restartPolicy: Never
```

### Image Update Automation

```yaml
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: app=registry.example.com/express-app
    argocd-image-updater.argoproj.io/app.update-strategy: semver
```

## Scaffolder Patterns

```yaml
patterns:
  application: "argocd/application.yaml"
  applicationset: "argocd/applicationset.yaml"
```

## Additional Dos

- DO use ApplicationSet for multi-environment Express deployments
- DO run database migrations as ArgoCD PreSync hooks
- DO use Image Updater for automated image promotion
- DO configure `selfHeal: true` to revert manual changes

## Additional Don'ts

- DON'T put secrets in the Git deploy repository -- use Sealed Secrets or External Secrets
- DON'T auto-sync production without a manual approval gate
- DON'T skip the migration PreSync hook when using Prisma/TypeORM
