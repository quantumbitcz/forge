# Helm with NestJS

> Extends `modules/container-orchestration/helm.md` with NestJS Helm chart patterns.
> Generic Helm conventions (chart structure, templating, release management) are NOT repeated here.

## Integration Setup

```yaml
# values.yaml
replicaCount: 2

image:
  repository: registry.example.com/nestjs-app
  tag: latest

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
          command: ["npx", "typeorm", "migration:run", "-d", "dist/data-source.js"]
          envFrom:
            - secretRef:
                name: {{ .Release.Name }}-db
      restartPolicy: Never
  backoffLimit: 3
```

### Swagger Endpoint Configuration

```yaml
# templates/configmap.yaml
data:
  NODE_ENV: production
  SWAGGER_ENABLED: {{ .Values.swagger.enabled | default "false" | quote }}
```

Disable Swagger UI in production for security. Enable conditionally per environment via Helm values.

## Scaffolder Patterns

```yaml
patterns:
  chart: "helm/{chart-name}/Chart.yaml"
  values: "helm/{chart-name}/values.yaml"
  deployment: "helm/{chart-name}/templates/deployment.yaml"
```

## Additional Dos

- DO use aggressive startup probes -- NestJS starts fast
- DO run database migrations as Helm pre-install/pre-upgrade hooks
- DO disable Swagger UI in production via environment variable
- DO call `enableShutdownHooks()` for Kubernetes SIGTERM handling

## Additional Don'ts

- DON'T expose Swagger UI in production without authentication
- DON'T hardcode database URLs in ConfigMap -- use Secrets
- DON'T set memory limits below 128Mi for NestJS applications
