# Rancher with ASP.NET

> Extends `modules/container-orchestration/rancher.md` with ASP.NET Core multi-cluster deployment patterns.
> Generic Rancher conventions (cluster provisioning, RBAC, monitoring) are NOT repeated here.

## Integration Setup

```yaml
# fleet/fleet.yaml
defaultNamespace: production
helm:
  releaseName: aspnet-app
  chart: charts/aspnet-app
  valuesFiles:
    - values.yaml
  values:
    image:
      repository: registry.example.com/aspnet-app
      tag: latest
    env:
      ASPNETCORE_ENVIRONMENT: Production
      ASPNETCORE_URLS: http://+:8080
targetCustomizations:
  - name: staging
    clusterSelector:
      matchLabels:
        env: staging
    helm:
      valuesFiles:
        - values-staging.yaml
      values:
        env:
          ASPNETCORE_ENVIRONMENT: Staging
```

## Framework-Specific Patterns

### Fleet GitOps for ASP.NET

```yaml
# fleet/gitrepo.yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: aspnet-app
  namespace: fleet-default
spec:
  repo: https://github.com/org/aspnet-app.git
  branch: main
  paths:
    - deploy/charts/
  targets:
    - name: dev
      clusterSelector:
        matchLabels:
          env: dev
    - name: production
      clusterSelector:
        matchLabels:
          env: production
```

### Environment Configuration per Cluster

```yaml
# values-production.yaml
env:
  - name: ASPNETCORE_ENVIRONMENT
    value: Production
  - name: ASPNETCORE_URLS
    value: http://+:8080
  - name: DOTNET_EnableDiagnostics
    value: "0"
resources:
  requests:
    memory: 256Mi
    cpu: 250m
  limits:
    memory: 512Mi
    cpu: "1"
```

Disable diagnostics in production with `DOTNET_EnableDiagnostics=0`. Each cluster targets a different ASP.NET environment via `ASPNETCORE_ENVIRONMENT`.

### Rancher Apps Catalog for ASP.NET

```yaml
# Chart.yaml
apiVersion: v2
name: aspnet-app
version: 1.0.0
appVersion: "1.0.0"
annotations:
  catalog.cattle.io/display-name: ASP.NET Application
  catalog.cattle.io/os: linux
```

### EF Core Migration as Fleet Pre-Hook

```yaml
# templates/migration-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-migrate
  annotations:
    helm.sh/hook: pre-install,pre-upgrade
    helm.sh/hook-delete-policy: before-hook-creation
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

## Scaffolder Patterns

```yaml
patterns:
  fleet_config: "fleet/fleet.yaml"
  gitrepo: "fleet/gitrepo.yaml"
  values_prod: "deploy/charts/aspnet-app/values-production.yaml"
```

## Additional Dos

- DO set `ASPNETCORE_ENVIRONMENT` per cluster via Fleet `targetCustomizations`
- DO listen on port 8080 (non-privileged) across all clusters
- DO use Helm pre-install hooks for EF Core migrations in Fleet deployments
- DO disable diagnostics in production clusters

## Additional Don'ts

- DON'T use `Development` environment in production clusters
- DON'T hardcode connection strings -- use Kubernetes Secrets referenced in values
- DON'T skip health probes -- Fleet relies on them for deployment status
- DON'T deploy without migration hooks -- schema drift across clusters causes failures
