# Helm with Gin

> Extends `modules/container-orchestration/helm.md` with Gin Helm chart patterns.
> Generic Helm conventions (chart structure, templating, release management) are NOT repeated here.

## Integration Setup

```yaml
# values.yaml
replicaCount: 3

image:
  repository: registry.example.com/gin-app
  tag: latest

service:
  port: 8080

resources:
  requests:
    memory: 16Mi
    cpu: 50m
  limits:
    memory: 128Mi
    cpu: 500m
```

## Framework-Specific Patterns

### Health Probes

```yaml
containers:
  - name: {{ .Chart.Name }}
    env:
      - name: GIN_MODE
        value: release
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
      periodSeconds: 1
      failureThreshold: 5
```

### Migration Job

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
          command: ["/server", "--migrate"]
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

- DO set low memory requests -- Go has minimal runtime overhead
- DO use 1s startup probe intervals -- Go starts instantly
- DO set `GIN_MODE=release` via ConfigMap

## Additional Don'ts

- DON'T over-provision memory
- DON'T set `GIN_MODE=debug` in production values
