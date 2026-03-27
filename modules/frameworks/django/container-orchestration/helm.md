# Helm with Django

> Extends `modules/container-orchestration/helm.md` with Django Helm chart patterns.
> Generic Helm conventions (chart structure, templating, release management) are NOT repeated here.

## Integration Setup

```yaml
# Chart.yaml
apiVersion: v2
name: django-app
version: 1.0.0
appVersion: "4.2"
description: Django application Helm chart
```

```yaml
# values.yaml
replicaCount: 2

image:
  repository: registry.example.com/django-app
  tag: latest
  pullPolicy: IfNotPresent

django:
  settingsModule: config.settings.production
  gunicornWorkers: 4
  allowedHosts: "*"

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
    env:
      - name: DJANGO_SETTINGS_MODULE
        value: {{ .Values.django.settingsModule | quote }}
      - name: DJANGO_ALLOWED_HOSTS
        value: {{ .Values.django.allowedHosts | quote }}
    ports:
      - name: http
        containerPort: 8000
    livenessProbe:
      httpGet:
        path: /health/
        port: http
      periodSeconds: 10
      failureThreshold: 3
    readinessProbe:
      httpGet:
        path: /health/
        port: http
      periodSeconds: 5
      failureThreshold: 3
    startupProbe:
      httpGet:
        path: /health/
        port: http
      periodSeconds: 2
      failureThreshold: 15
    resources:
      {{- toYaml .Values.resources | nindent 6 }}
```

### Django Migration Job

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

### Environment Configuration via ConfigMap

```yaml
# templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-config
data:
  DJANGO_SETTINGS_MODULE: {{ .Values.django.settingsModule | quote }}
  GUNICORN_WORKERS: {{ .Values.django.gunicornWorkers | quote }}
  DJANGO_ALLOWED_HOSTS: {{ .Values.django.allowedHosts | quote }}
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

- DO run Django migrations as a Helm pre-install/pre-upgrade hook
- DO set `DJANGO_SETTINGS_MODULE` and `DJANGO_ALLOWED_HOSTS` via ConfigMap
- DO use Secrets for `SECRET_KEY` and `DATABASE_URL`
- DO use `startupProbe` with aggressive intervals -- Gunicorn starts fast

## Additional Don'ts

- DON'T hardcode `SECRET_KEY` in values.yaml -- use a Secret resource
- DON'T skip the migration hook -- schema drift causes application errors
- DON'T set `DJANGO_ALLOWED_HOSTS` to `*` in production -- whitelist actual hostnames
