# ArgoCD with Django

> Extends `modules/container-orchestration/argocd.md` with Django GitOps deployment patterns.
> Generic ArgoCD conventions (Application CRDs, sync policies, project scoping) are NOT repeated here.

## Integration Setup

```yaml
# argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: django-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/django-app-deploy
    targetRevision: main
    path: helm/django-app
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

### Django Migration as PreSync Hook

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
          command: ["python", "manage.py", "migrate", "--noinput"]
          env:
            - name: DJANGO_SETTINGS_MODULE
              value: {{ .Values.django.settingsModule | quote }}
          envFrom:
            - secretRef:
                name: {{ .Release.Name }}-db
      restartPolicy: Never
  backoffLimit: 3
```

### Multi-Environment ApplicationSet

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: django-app
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
      name: "django-app-{{env}}"
    spec:
      source:
        repoURL: https://github.com/org/django-app-deploy
        targetRevision: main
        path: helm/django-app
        helm:
          valueFiles:
            - values.yaml
            - "values-{{env}}.yaml"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{namespace}}"
```

### Environment Values

```yaml
# values-production.yaml
django:
  settingsModule: config.settings.production
  gunicornWorkers: 4
  allowedHosts: "app.example.com"
replicaCount: 3
```

## Scaffolder Patterns

```yaml
patterns:
  application: "argocd/application.yaml"
  applicationset: "argocd/applicationset.yaml"
  values_env: "helm/{chart-name}/values-{env}.yaml"
```

## Additional Dos

- DO run Django migrations as ArgoCD PreSync hooks
- DO use ApplicationSet for multi-environment Django deployments
- DO set `DJANGO_SETTINGS_MODULE` per environment via values overlays
- DO configure `selfHeal: true` to revert manual Kubernetes changes

## Additional Don'ts

- DON'T put `SECRET_KEY` or `DATABASE_URL` in Git -- use Sealed Secrets or External Secrets
- DON'T auto-sync production without a manual approval gate
- DON'T skip the migration PreSync hook -- schema drift causes application errors
