# ArgoCD with Next.js

> Extends `modules/container-orchestration/argocd.md` with Next.js GitOps deployment patterns.
> Generic ArgoCD conventions (Application CRDs, sync policies, project scoping) are NOT repeated here.

## Integration Setup

```yaml
# argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nextjs-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/nextjs-app-deploy
    targetRevision: main
    path: helm/nextjs-app
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

### Prisma Migration as PreSync Hook

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
    argocd-image-updater.argoproj.io/image-list: app=registry.example.com/nextjs-app
    argocd-image-updater.argoproj.io/app.update-strategy: semver
```

### Vercel vs Self-Hosted

For Vercel deployments, ArgoCD manages the backend infrastructure only. For self-hosted, ArgoCD manages the full Next.js deployment including ISR cache volumes.

## Scaffolder Patterns

```yaml
patterns:
  application: "argocd/application.yaml"
  values_env: "helm/{chart-name}/values-{env}.yaml"
```

## Additional Dos

- DO run Prisma migrations as PreSync hooks
- DO use Image Updater for automated promotion
- DO configure ISR cache PVC in the Helm values
- DO configure `selfHeal: true`

## Additional Don'ts

- DON'T put database URLs in Git -- use Sealed Secrets or External Secrets
- DON'T auto-sync production without approval gates
- DON'T embed `NEXT_PUBLIC_*` secrets in the deploy repository
