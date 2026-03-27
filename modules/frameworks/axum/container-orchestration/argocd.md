# ArgoCD with Axum

> Extends `modules/container-orchestration/argocd.md` with Axum GitOps deployment patterns.
> Generic ArgoCD conventions (Application CRDs, sync policies, project scoping) are NOT repeated here.

## Integration Setup

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: axum-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/axum-app-deploy
    targetRevision: main
    path: helm/axum-app
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

### SQLx Migration as PreSync

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          command: ["/app", "--migrate"]
          envFrom:
            - secretRef:
                name: {{ .Release.Name }}-db
      restartPolicy: Never
```

### Image Update Automation

```yaml
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: app=registry.example.com/axum-app
    argocd-image-updater.argoproj.io/app.update-strategy: semver
```

## Scaffolder Patterns

```yaml
patterns:
  application: "argocd/application.yaml"
```

## Additional Dos

- DO run SQLx migrations as PreSync hooks
- DO use Image Updater for automated promotion
- DO configure `selfHeal: true`

## Additional Don'ts

- DON'T put database URLs in Git
- DON'T auto-sync production without approval gates
