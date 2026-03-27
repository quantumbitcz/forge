# Helm with ASP.NET

> Extends `modules/container-orchestration/helm.md` with ASP.NET Core Helm chart patterns.
> Generic Helm conventions (chart structure, templating, release management) are NOT repeated here.

## Integration Setup

```yaml
# values.yaml
replicaCount: 2

image:
  repository: registry.example.com/aspnet-app
  tag: latest

aspnet:
  environment: Production
  port: 8080

resources:
  requests:
    memory: 128Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: "1"
```

## Framework-Specific Patterns

### Health Probes

```yaml
# templates/deployment.yaml (snippet)
containers:
  - name: {{ .Chart.Name }}
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
    env:
      - name: ASPNETCORE_ENVIRONMENT
        value: {{ .Values.aspnet.environment | quote }}
      - name: ASPNETCORE_URLS
        value: "http://+:{{ .Values.aspnet.port }}"
    ports:
      - name: http
        containerPort: {{ .Values.aspnet.port }}
    livenessProbe:
      httpGet:
        path: /health
        port: http
      periodSeconds: 10
      failureThreshold: 3
    readinessProbe:
      httpGet:
        path: /health/ready
        port: http
      periodSeconds: 5
      failureThreshold: 3
    startupProbe:
      httpGet:
        path: /health
        port: http
      periodSeconds: 2
      failureThreshold: 15
```

Use separate `/health` (liveness) and `/health/ready` (readiness with DB checks) endpoints.

### EF Core Migration Job

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

### Configuration via ConfigMap

```yaml
# templates/configmap.yaml
data:
  ASPNETCORE_ENVIRONMENT: {{ .Values.aspnet.environment | quote }}
  DOTNET_EnableDiagnostics: "0"
  Logging__LogLevel__Default: {{ .Values.logLevel | default "Information" | quote }}
```

## Scaffolder Patterns

```yaml
patterns:
  chart: "helm/{chart-name}/Chart.yaml"
  values: "helm/{chart-name}/values.yaml"
  deployment: "helm/{chart-name}/templates/deployment.yaml"
  migration_job: "helm/{chart-name}/templates/migration-job.yaml"
```

## Additional Dos

- DO use separate liveness and readiness health check endpoints
- DO run EF Core migrations as Helm pre-install/pre-upgrade hooks
- DO use Secrets for connection strings and credentials
- DO set `DOTNET_EnableDiagnostics=0` in production

## Additional Don'ts

- DON'T hardcode connection strings in ConfigMap -- use Secrets
- DON'T use `ASPNETCORE_ENVIRONMENT=Development` in production values
- DON'T skip the migration hook when using EF Core
