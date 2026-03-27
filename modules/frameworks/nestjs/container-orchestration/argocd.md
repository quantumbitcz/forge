# ArgoCD with NestJS

> Extends `modules/container-orchestration/argocd.md` with NestJS GitOps deployment patterns.
> Generic ArgoCD conventions (Application CRDs, sync policies, project scoping) are NOT repeated here.

## Integration Setup

```yaml
# argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nestjs-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/nestjs-app-deploy
    targetRevision: main
    path: helm/nestjs-app
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
```

## Framework-Specific Patterns

### Migration as PreSync Hook

```yaml
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
          command: ["npx", "typeorm", "migration:run", "-d", "dist/data-source.js"]
          envFrom:
            - secretRef:
                name: {{ .Release.Name }}-db
      restartPolicy: Never
```

### Swagger Toggle per Environment

```yaml
# values-dev.yaml
swagger:
  enabled: "true"

# values-production.yaml
swagger:
  enabled: "false"
```

### Image Update Automation

```yaml
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: app=registry.example.com/nestjs-app
    argocd-image-updater.argoproj.io/app.update-strategy: semver
```

## Scaffolder Patterns

```yaml
patterns:
  application: "argocd/application.yaml"
  values_env: "helm/{chart-name}/values-{env}.yaml"
```

## Additional Dos

- DO run database migrations as ArgoCD PreSync hooks
- DO toggle Swagger UI per environment via values overlays
- DO use Image Updater for automated promotion
- DO configure `selfHeal: true`

## Additional Don'ts

- DON'T enable Swagger UI in production without authentication
- DON'T put secrets in the Git deploy repository
- DON'T auto-sync production without approval gates
