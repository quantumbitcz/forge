# Helm with Vapor

> Extends `modules/container-orchestration/helm.md` with Vapor Helm chart patterns.
> Generic Helm conventions (chart structure, templating, release management) are NOT repeated here.

## Integration Setup

```yaml
# values.yaml
replicaCount: 2

image:
  repository: registry.example.com/vapor-app
  tag: latest

vapor:
  env: production
  port: 8080

resources:
  requests:
    memory: 64Mi
    cpu: 100m
  limits:
    memory: 256Mi
    cpu: 500m
```

## Framework-Specific Patterns

### Health Probes

```yaml
containers:
  - name: {{ .Chart.Name }}
    env:
      - name: VAPOR_ENV
        value: {{ .Values.vapor.env | quote }}
    ports:
      - name: http
        containerPort: {{ .Values.vapor.port }}
    livenessProbe:
      httpGet:
        path: /health
        port: http
      periodSeconds: 10
    readinessProbe:
      httpGet:
        path: /health
        port: http
      periodSeconds: 5
    startupProbe:
      httpGet:
        path: /health
        port: http
      periodSeconds: 2
      failureThreshold: 10
```

### Fluent Migration Job

```yaml
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
          command: ["./App", "migrate", "--yes"]
          envFrom:
            - secretRef:
                name: {{ .Release.Name }}-db
      restartPolicy: Never
```

## Scaffolder Patterns

```yaml
patterns:
  chart: "helm/{chart-name}/Chart.yaml"
  values: "helm/{chart-name}/values.yaml"
```

## Additional Dos

- DO run Fluent migrations as Helm hooks
- DO set `VAPOR_ENV` via ConfigMap
- DO use Secrets for database URLs

## Additional Don'ts

- DON'T set `VAPOR_ENV=development` in production
- DON'T skip migration hooks
