# Helm with FastAPI

> Extends `modules/container-orchestration/helm.md` with FastAPI Helm chart patterns.
> Generic Helm conventions (chart structure, templating, release management) are NOT repeated here.

## Integration Setup

```yaml
# Chart.yaml
apiVersion: v2
name: fastapi-app
version: 1.0.0
appVersion: "0.1.0"
description: FastAPI application Helm chart
```

```yaml
# values.yaml
replicaCount: 2

image:
  repository: registry.example.com/fastapi-app
  tag: latest
  pullPolicy: IfNotPresent

uvicorn:
  workers: 4
  port: 8000

resources:
  requests:
    memory: 256Mi
    cpu: 250m
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
    ports:
      - name: http
        containerPort: {{ .Values.uvicorn.port }}
    livenessProbe:
      httpGet:
        path: /health
        port: http
      periodSeconds: 10
      failureThreshold: 3
    readinessProbe:
      httpGet:
        path: /health
        port: http
      periodSeconds: 5
      failureThreshold: 3
    startupProbe:
      httpGet:
        path: /health
        port: http
      periodSeconds: 2
      failureThreshold: 10
    resources:
      {{- toYaml .Values.resources | nindent 6 }}
```

FastAPI starts in under a second, so `startupProbe` can be aggressive (2s intervals, 10 failures = 20s max).

### Environment Configuration via ConfigMap

```yaml
# templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-config
data:
  UVICORN_WORKERS: {{ .Values.uvicorn.workers | quote }}
  LOG_LEVEL: {{ .Values.logLevel | default "info" | quote }}
```

### Database URL via Secret

```yaml
# templates/secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Release.Name }}-db
type: Opaque
stringData:
  DATABASE_URL: {{ .Values.database.url | quote }}
```

### Alembic Migration Job

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
          command: ["alembic", "upgrade", "head"]
          envFrom:
            - secretRef:
                name: {{ .Release.Name }}-db
      restartPolicy: Never
  backoffLimit: 3
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

- DO use aggressive startup probes -- FastAPI starts in under a second
- DO run Alembic migrations as a Helm pre-install/pre-upgrade hook
- DO set Uvicorn workers via ConfigMap environment variable
- DO use Secrets for database URLs and credentials

## Additional Don'ts

- DON'T set `initialDelaySeconds` on liveness/readiness probes -- use `startupProbe` instead
- DON'T hardcode database URLs in ConfigMap -- use Secrets for anything with credentials
- DON'T skip the migration job -- schema drift causes application startup failures
