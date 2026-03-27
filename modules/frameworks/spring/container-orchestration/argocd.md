# ArgoCD with Spring

> Extends `modules/container-orchestration/argocd.md` with Spring Boot GitOps deployment patterns.
> Generic ArgoCD conventions (Application CRDs, sync policies, project scoping) are NOT repeated here.

## Integration Setup

```yaml
# argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: spring-boot-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/spring-app-deploy
    targetRevision: main
    path: helm/spring-app
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

### Environment-Specific Values Overlays

```
deploy-repo/
  helm/spring-app/
    Chart.yaml
    values.yaml              # base: image, resource defaults
    values-dev.yaml          # SPRING_PROFILES_ACTIVE=dev, 1 replica
    values-staging.yaml      # SPRING_PROFILES_ACTIVE=staging, 2 replicas
    values-production.yaml   # SPRING_PROFILES_ACTIVE=production, 3 replicas
    templates/
      deployment.yaml
      service.yaml
      configmap.yaml
```

```yaml
# ArgoCD ApplicationSet for multi-environment
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: spring-boot-app
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: dev
            namespace: dev
            cluster: https://kubernetes.default.svc
          - env: staging
            namespace: staging
            cluster: https://kubernetes.default.svc
          - env: production
            namespace: production
            cluster: https://prod-cluster.example.com
  template:
    metadata:
      name: "spring-app-{{env}}"
    spec:
      project: default
      source:
        repoURL: https://github.com/org/spring-app-deploy
        targetRevision: main
        path: helm/spring-app
        helm:
          valueFiles:
            - values.yaml
            - "values-{{env}}.yaml"
      destination:
        server: "{{cluster}}"
        namespace: "{{namespace}}"
```

### Spring Profiles Mapped to ArgoCD Environments

Each ArgoCD Application maps to a Spring profile through the values overlay:

```yaml
# values-production.yaml
spring:
  profiles: production
replicaCount: 3
resources:
  requests:
    memory: 1Gi
  limits:
    memory: 2Gi
```

The Helm chart injects `SPRING_PROFILES_ACTIVE` from `spring.profiles`, ensuring each ArgoCD-managed environment activates the correct Spring configuration.

### Actuator Health Checks for Sync Health

ArgoCD monitors Kubernetes resource health to determine sync status. Spring Boot Actuator health probes feed into pod health:

```yaml
# Deployment health probes (in Helm template)
startupProbe:
  httpGet:
    path: /actuator/health/liveness
    port: 8080
  periodSeconds: 5
  failureThreshold: 30

livenessProbe:
  httpGet:
    path: /actuator/health/liveness
    port: 8080
  periodSeconds: 10
  failureThreshold: 5

readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: 8080
  periodSeconds: 5
  failureThreshold: 3
```

ArgoCD considers a Deployment "Healthy" when all pods pass readiness. If Spring Boot's readiness probe fails (e.g., database unreachable), ArgoCD reports the Application as "Degraded" -- triggering alerts.

### Image Update Automation

```yaml
# argocd-image-updater annotation on Application
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: app=registry.example.com/spring-app
    argocd-image-updater.argoproj.io/app.update-strategy: semver
    argocd-image-updater.argoproj.io/app.helm.image-name: image.repository
    argocd-image-updater.argoproj.io/app.helm.image-tag: image.tag
```

ArgoCD Image Updater watches the container registry and updates the Application when new image tags match the semver strategy.

### Sync Waves for Database Migrations

```yaml
# templates/migration-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-db-migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          command: ["java", "-cp", "@/app/jib-classpath-file", "com.example.MigrateKt"]
      restartPolicy: Never
```

Use ArgoCD `PreSync` hooks to run Flyway/Liquibase migrations before the main application deploys. The migration job runs and completes before the Deployment is updated.

## Scaffolder Patterns

```yaml
patterns:
  application: "argocd/application.yaml"
  applicationset: "argocd/applicationset.yaml"
  values_env: "helm/{chart-name}/values-{env}.yaml"
```

## Additional Dos

- DO use ApplicationSet with list generator for multi-environment Spring Boot deployments
- DO run database migrations as ArgoCD PreSync hooks
- DO use ArgoCD Image Updater for automated image promotion across environments
- DO configure `selfHeal: true` so ArgoCD reverts manual Kubernetes changes

## Additional Don'ts

- DON'T put secrets in the Git deploy repository -- use Sealed Secrets or External Secrets Operator
- DON'T skip `startupProbe` -- ArgoCD will report the app as "Degraded" during slow Spring Boot startup
- DON'T use the same values file for all environments -- Spring profiles need distinct overlays
- DON'T auto-sync production without a manual approval gate or progressive delivery
