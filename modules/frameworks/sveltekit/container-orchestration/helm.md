# Helm with SvelteKit

> Extends `modules/container-orchestration/helm.md` with SvelteKit adapter-node Helm chart patterns.
> Generic Helm conventions (chart structure, templating, release management) are NOT repeated here.

## Integration Setup

```yaml
# Chart.yaml
apiVersion: v2
name: sveltekit-app
version: 1.0.0
appVersion: "2.0.0"
description: SvelteKit application Helm chart
```

```yaml
# values.yaml
replicaCount: 2

image:
  repository: registry.example.com/sveltekit-app
  tag: latest
  pullPolicy: IfNotPresent

service:
  port: 3000

env:
  NODE_ENV: production
  APP_PUBLIC_SITE_URL: https://example.com

resources:
  requests:
    memory: 128Mi
    cpu: 100m
  limits:
    memory: 256Mi
    cpu: 500m
```

## Framework-Specific Patterns

### Lightweight Resource Requirements

SvelteKit with `adapter-node` is a lightweight Node.js server. Memory requirements are significantly lower than JVM-based applications.

```yaml
# values-production.yaml
replicaCount: 3
resources:
  requests:
    memory: 128Mi
    cpu: 100m
  limits:
    memory: 256Mi
    cpu: 500m
```

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
        path: /
        port: http
      initialDelaySeconds: 5
      periodSeconds: 10
    readinessProbe:
      httpGet:
        path: /
        port: http
      initialDelaySeconds: 3
      periodSeconds: 5
    startupProbe:
      httpGet:
        path: /
        port: http
      initialDelaySeconds: 2
      periodSeconds: 2
      failureThreshold: 10
    resources:
      {{- toYaml .Values.resources | nindent 6 }}
```

SvelteKit starts fast -- `initialDelaySeconds` can be low (2-5s) compared to JVM apps (30-60s).

### Environment Configuration via ConfigMap

```yaml
# templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-config
data:
  {{- range $key, $value := .Values.env }}
  {{ $key }}: {{ $value | quote }}
  {{- end }}
```

SvelteKit reads `$env/dynamic/private` from environment variables at startup. Inject via ConfigMap environment references.

## Scaffolder Patterns

```yaml
patterns:
  chart: "helm/{chart-name}/Chart.yaml"
  values: "helm/{chart-name}/values.yaml"
  values_env: "helm/{chart-name}/values-{env}.yaml"
  deployment: "helm/{chart-name}/templates/deployment.yaml"
```

## Additional Dos

- DO use low `initialDelaySeconds` values -- SvelteKit starts in under 2 seconds
- DO set lightweight resource limits (128-256Mi memory) for SvelteKit apps
- DO use ConfigMap for non-secret `$env/dynamic/*` configuration
- DO use `startupProbe` to decouple startup tolerance from liveness checking

## Additional Don'ts

- DON'T over-provision resources for SvelteKit -- it's not a JVM app
- DON'T set `initialDelaySeconds` to 30+ seconds -- SvelteKit starts near-instantly
- DON'T hardcode environment values in the Docker image -- use Helm values
