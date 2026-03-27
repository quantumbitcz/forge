# Helm with Next.js

> Extends `modules/container-orchestration/helm.md` with Next.js Helm chart patterns.
> Generic Helm conventions (chart structure, templating, release management) are NOT repeated here.

## Integration Setup

```yaml
# values.yaml
replicaCount: 2

image:
  repository: registry.example.com/nextjs-app
  tag: latest

service:
  port: 3000

resources:
  requests:
    memory: 128Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: "1"

isr:
  enabled: true
  cacheSize: 1Gi
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
    env:
      - name: HOSTNAME
        value: "0.0.0.0"
    livenessProbe:
      httpGet:
        path: /api/health
        port: http
      periodSeconds: 10
      failureThreshold: 3
    readinessProbe:
      httpGet:
        path: /api/health
        port: http
      periodSeconds: 5
      failureThreshold: 3
    startupProbe:
      httpGet:
        path: /api/health
        port: http
      periodSeconds: 2
      failureThreshold: 10
```

### ISR Cache PVC

```yaml
# templates/pvc.yaml
{{- if .Values.isr.enabled }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .Release.Name }}-isr-cache
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: {{ .Values.isr.cacheSize }}
{{- end }}
```

```yaml
# In deployment.yaml
volumeMounts:
  - name: isr-cache
    mountPath: /app/.next/cache
volumes:
  - name: isr-cache
    {{- if .Values.isr.enabled }}
    persistentVolumeClaim:
      claimName: {{ .Release.Name }}-isr-cache
    {{- else }}
    emptyDir: {}
    {{- end }}
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
```

## Scaffolder Patterns

```yaml
patterns:
  chart: "helm/{chart-name}/Chart.yaml"
  values: "helm/{chart-name}/values.yaml"
  deployment: "helm/{chart-name}/templates/deployment.yaml"
```

## Additional Dos

- DO use ReadWriteMany PVC for ISR cache when running multiple replicas
- DO set `HOSTNAME=0.0.0.0` for container networking
- DO use aggressive startup probes -- Next.js starts fast
- DO run Prisma migrations as Helm pre-install/pre-upgrade hooks

## Additional Don'ts

- DON'T use emptyDir for ISR cache in production -- data is lost on pod restart
- DON'T hardcode `NEXT_PUBLIC_*` in Helm values -- they're build-time only
- DON'T skip the migration hook when using Prisma
