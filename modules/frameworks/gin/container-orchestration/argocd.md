# ArgoCD with Gin

> Extends `modules/container-orchestration/argocd.md` with Gin GitOps deployment patterns.
> Generic ArgoCD conventions (Application CRDs, sync policies, project scoping) are NOT repeated here.

## Integration Setup

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gin-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/gin-app-deploy
    targetRevision: main
    path: helm/gin-app
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Framework-Specific Patterns

### Migration as PreSync

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
          command: ["/server", "--migrate"]
          envFrom:
            - secretRef:
                name: {{ .Release.Name }}-db
      restartPolicy: Never
```

## Scaffolder Patterns

```yaml
patterns:
  application: "argocd/application.yaml"
```

## Additional Dos

- DO run migrations as PreSync hooks
- DO use Image Updater for automated promotion
- DO configure `selfHeal: true`

## Additional Don'ts

- DON'T put secrets in Git
- DON'T auto-sync production without approval gates
