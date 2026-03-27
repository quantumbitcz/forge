# ArgoCD with ASP.NET

> Extends `modules/container-orchestration/argocd.md` with ASP.NET Core GitOps deployment patterns.
> Generic ArgoCD conventions (Application CRDs, sync policies, project scoping) are NOT repeated here.

## Integration Setup

```yaml
# argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: aspnet-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/aspnet-app-deploy
    targetRevision: main
    path: helm/aspnet-app
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

### EF Core Migration as PreSync Hook

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
          command: ["dotnet", "MyApp.Api.dll", "--migrate"]
          envFrom:
            - secretRef:
                name: {{ .Release.Name }}-db
      restartPolicy: Never
```

### Environment Values

```yaml
# values-production.yaml
aspnet:
  environment: Production
replicaCount: 3
```

### Image Update Automation

```yaml
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: app=registry.example.com/aspnet-app
    argocd-image-updater.argoproj.io/app.update-strategy: semver
```

## Scaffolder Patterns

```yaml
patterns:
  application: "argocd/application.yaml"
  values_env: "helm/{chart-name}/values-{env}.yaml"
```

## Additional Dos

- DO run EF Core migrations as PreSync hooks
- DO set `ASPNETCORE_ENVIRONMENT` per environment via values
- DO use Image Updater for automated promotion
- DO configure `selfHeal: true`

## Additional Don'ts

- DON'T put connection strings in Git -- use Sealed Secrets
- DON'T auto-sync production without approval gates
- DON'T skip the migration PreSync hook
