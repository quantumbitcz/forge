# Helm with Express

> Extends `modules/container-orchestration/helm.md` with Express Helm chart patterns.
> Generic Helm conventions (chart structure, templating, release management) are NOT repeated here.

## Integration Setup

```yaml
# Chart.yaml
apiVersion: v2
name: express-app
version: 1.0.0
appVersion: "1.0.0"
description: Express application Helm chart
```

```yaml
# values.yaml
replicaCount: 2

image:
  repository: registry.example.com/express-app
  tag: latest
  pullPolicy: IfNotPresent

service:
  port: 3000

resources:
  requests:
    memory: 128Mi
    cpu: 100m
  limits:
    memory: 256Mi
    cpu: 500m
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
        containerPort: {{ .Values.service.port }}
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

Node.js starts in under a second, so startup probes can be aggressive.

### Environment Configuration

```yaml
# templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-config
data:
  NODE_ENV: production
  LOG_LEVEL: {{ .Values.logLevel | default "info" | quote }}
  PORT: {{ .Values.service.port | quote }}
```

### Database Migration Job

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
          command: ["npx", "prisma", "migrate", "deploy"]
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
```

## Additional Dos

- DO use aggressive startup probes -- Node.js starts in under a second
- DO use Secrets for database URLs and credentials
- DO run database migrations as Helm pre-install/pre-upgrade hooks
- DO set `NODE_ENV=production` via ConfigMap

## Additional Don'ts

- DON'T set memory limits below 128Mi -- Node.js has baseline memory overhead
- DON'T hardcode database URLs in ConfigMap -- use Secrets
- DON'T skip graceful shutdown handling -- Kubernetes sends SIGTERM before killing pods
