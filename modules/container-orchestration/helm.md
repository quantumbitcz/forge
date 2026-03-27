# Helm

## Overview

Helm is the package manager for Kubernetes. It packages Kubernetes manifests into versioned, parameterized bundles called charts, enabling teams to template, share, install, upgrade, and rollback complex Kubernetes deployments with a single command. Helm transforms raw YAML manifests — which are verbose, repetitive, and environment-specific — into reusable, configurable packages that can be distributed via chart repositories or OCI registries.

Use Helm when deploying applications to Kubernetes that require environment-specific configuration (dev/staging/prod), when managing third-party application deployments (databases, monitoring stacks, ingress controllers), when sharing deployment configurations across teams, and when needing atomic install/upgrade/rollback semantics with release history. Helm's templating engine (Go templates with Sprig functions) enables a single chart to produce manifests for any environment by varying a values file.

Do not use Helm for simple applications with one or two manifests — raw YAML or Kustomize overlays are simpler. Do not use Helm when the team cannot maintain chart quality — poorly written charts with inadequate templating, missing defaults, and no schema validation become a maintenance burden worse than raw manifests. Do not use Helm 2 — it required Tiller (a cluster-side component with cluster-admin privileges), which was a critical security risk. Helm 3 eliminated Tiller entirely, storing release state in Kubernetes secrets within the target namespace.

Key differentiators: (1) Charts are versioned artifacts with semantic versioning, enabling reproducible deployments and rollbacks. (2) Helm's release management tracks every install and upgrade, enabling `helm rollback` to any previous revision. (3) Library charts share common templates (labels, annotations, resource names) across multiple charts without code duplication. (4) Helm hooks execute jobs at specific lifecycle points (pre-install, post-upgrade, pre-delete) for database migrations, smoke tests, and cleanup. (5) OCI registry support (GA since Helm 3.8) distributes charts alongside container images in the same registry infrastructure. (6) Helmfile orchestrates multi-chart deployments declaratively, managing release ordering, dependencies, and environment-specific overrides.

## Architecture Patterns

### Chart Structure

A Helm chart is a directory with a predefined structure containing templates, default values, metadata, and optional CRDs. Understanding the structure is essential for creating maintainable, well-tested charts.

**Standard chart directory:**
```
myapp/
  Chart.yaml              # Chart metadata (name, version, appVersion, dependencies)
  Chart.lock              # Locked dependency versions
  values.yaml             # Default values (overridden per environment)
  values.schema.json      # JSON Schema for values validation
  templates/
    _helpers.tpl          # Shared template definitions (names, labels, selectors)
    deployment.yaml       # Deployment manifest template
    service.yaml          # Service manifest template
    ingress.yaml          # Ingress manifest template (conditional)
    hpa.yaml              # HorizontalPodAutoscaler (conditional)
    serviceaccount.yaml   # ServiceAccount (conditional)
    configmap.yaml        # ConfigMap template
    secret.yaml           # Secret template
    pdb.yaml              # PodDisruptionBudget
    networkpolicy.yaml    # NetworkPolicy (conditional)
    tests/
      test-connection.yaml  # Helm test pod
  crds/                   # Custom Resource Definitions (applied before templates)
  charts/                 # Packaged dependency charts
```

**`Chart.yaml`:**
```yaml
apiVersion: v2
name: myapp
description: A Helm chart for MyApp API server
type: application
version: 0.3.0          # Chart version (semver)
appVersion: "1.2.3"     # Application version
kubeVersion: ">=1.28.0"
maintainers:
  - name: Team Platform
    email: platform@example.com
dependencies:
  - name: postgresql
    version: "16.2.1"
    repository: "oci://registry-1.docker.io/bitnamicharts"
    condition: postgresql.enabled
  - name: redis
    version: "20.4.0"
    repository: "oci://registry-1.docker.io/bitnamicharts"
    condition: redis.enabled
```

**`values.yaml` with schema enforcement:**
```yaml
replicaCount: 2

image:
  repository: registry.example.com/myapp
  tag: ""          # Defaults to Chart.appVersion
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 8080

ingress:
  enabled: false
  className: nginx
  annotations: {}
  hosts:
    - host: myapp.example.com
      paths:
        - path: /
          pathType: Prefix
  tls: []

resources:
  limits:
    cpu: "2"
    memory: 1Gi
  requests:
    cpu: 500m
    memory: 512Mi

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

postgresql:
  enabled: true

redis:
  enabled: true

env: {}
secretEnv: {}
```

**`values.schema.json`** for validation:
```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["image", "service", "resources"],
  "properties": {
    "replicaCount": {
      "type": "integer",
      "minimum": 1
    },
    "image": {
      "type": "object",
      "required": ["repository"],
      "properties": {
        "repository": { "type": "string", "minLength": 1 },
        "tag": { "type": "string" },
        "pullPolicy": { "type": "string", "enum": ["Always", "IfNotPresent", "Never"] }
      }
    },
    "resources": {
      "type": "object",
      "required": ["limits", "requests"]
    }
  }
}
```

### Template Patterns and Helpers

The `_helpers.tpl` file defines reusable named templates that standardize labels, names, and selectors across all manifests. This is the single most important file for chart maintainability — all resource names and label selectors should derive from these helpers.

**`templates/_helpers.tpl`:**
```yaml
{{/*
Expand the name of the chart.
*/}}
{{- define "myapp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "myapp.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "myapp.labels" -}}
helm.sh/chart: {{ include "myapp.chart" . }}
{{ include "myapp.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "myapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "myapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Chart label
*/}}
{{- define "myapp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}
```

**`templates/deployment.yaml`:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "myapp.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      labels:
        {{- include "myapp.labels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "myapp.fullname" . }}
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        fsGroup: 1001
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.service.port }}
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: http
            initialDelaySeconds: 15
            periodSeconds: 5
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          env:
            {{- range $key, $value := .Values.env }}
            - name: {{ $key }}
              value: {{ $value | quote }}
            {{- end }}
          envFrom:
            {{- if .Values.secretEnv }}
            - secretRef:
                name: {{ include "myapp.fullname" . }}-env
            {{- end }}
```

### Helm Hooks

Hooks execute Kubernetes resources at specific lifecycle points during a release. They are annotated with `helm.sh/hook` and are commonly used for database migrations, integration tests, and cleanup tasks.

```yaml
# templates/job-migrate.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "myapp.fullname" . }}-migrate
  annotations:
    "helm.sh/hook": pre-upgrade,pre-install
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          command: ["./migrate", "--target", "latest"]
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: {{ include "myapp.fullname" . }}-db
                  key: url
```

**Hook types:**
- `pre-install` / `post-install` — run before/after first install
- `pre-upgrade` / `post-upgrade` — run before/after upgrade
- `pre-delete` / `post-delete` — run before/after uninstall
- `pre-rollback` / `post-rollback` — run before/after rollback
- `test` — run with `helm test`

**Hook ordering** is controlled by `helm.sh/hook-weight` — lower weights execute first. The `hook-delete-policy` controls when hook resources are garbage collected: `before-hook-creation` (default — delete previous hook before running new one), `hook-succeeded` (delete after success), `hook-failed` (delete after failure).

### Library Charts and Chart Testing

Library charts provide reusable template definitions without producing any manifest output. They solve the DRY problem across multiple application charts that share common patterns (labels, security contexts, probes).

**Library chart (`Chart.yaml`):**
```yaml
apiVersion: v2
name: common-lib
type: library
version: 1.0.0
description: Shared templates for all application charts
```

**Using a library chart:**
```yaml
# Application Chart.yaml
dependencies:
  - name: common-lib
    version: "1.x.x"
    repository: "oci://registry.example.com/charts"
```

**Chart testing with `helm test`:**
```yaml
# templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "myapp.fullname" . }}-test-connection
  annotations:
    "helm.sh/hook": test
spec:
  restartPolicy: Never
  containers:
    - name: wget
      image: busybox:1.37
      command: ['wget']
      args: ['{{ include "myapp.fullname" . }}:{{ .Values.service.port }}/actuator/health']
```

```bash
# Run chart tests after install
helm test myapp-release

# Chart Testing tool (ct) for CI — validates chart quality
ct lint --charts ./charts/myapp
ct install --charts ./charts/myapp
```

### Helmfile for Multi-Chart Deployments

Helmfile is a declarative tool for deploying multiple Helm charts as a coordinated set. It manages release ordering, environment-specific values, and shared configuration across an entire cluster's application portfolio.

```yaml
# helmfile.yaml
environments:
  dev:
    values:
      - environments/dev/values.yaml
  staging:
    values:
      - environments/staging/values.yaml
  production:
    values:
      - environments/production/values.yaml

repositories:
  - name: bitnami
    url: https://charts.bitnami.com/bitnami
  - name: ingress-nginx
    url: https://kubernetes.github.io/ingress-nginx

releases:
  - name: ingress
    namespace: ingress-system
    chart: ingress-nginx/ingress-nginx
    version: 4.11.3
    values:
      - ingress/values.yaml

  - name: postgresql
    namespace: database
    chart: bitnami/postgresql
    version: 16.2.1
    values:
      - database/values.yaml
      - database/{{ .Environment.Name }}.yaml

  - name: myapp
    namespace: myapp
    chart: ./charts/myapp
    needs:
      - database/postgresql
      - ingress-system/ingress
    values:
      - apps/myapp/values.yaml
      - apps/myapp/{{ .Environment.Name }}.yaml
    secrets:
      - apps/myapp/secrets.{{ .Environment.Name }}.yaml
```

```bash
# Deploy all releases for an environment
helmfile -e production apply

# Diff before applying
helmfile -e production diff

# Sync specific release
helmfile -e production -l name=myapp sync

# Destroy all releases
helmfile -e staging destroy
```

## Configuration

### Development

Development Helm usage focuses on rapid iteration with local charts and overrides.

```bash
# Install from local chart directory with dev values
helm install myapp-dev ./charts/myapp \
  -f ./charts/myapp/values-dev.yaml \
  --set image.tag=latest \
  --namespace dev --create-namespace

# Upgrade after chart changes
helm upgrade myapp-dev ./charts/myapp \
  -f ./charts/myapp/values-dev.yaml \
  --namespace dev

# Render templates locally without installing (debugging)
helm template myapp-dev ./charts/myapp \
  -f ./charts/myapp/values-dev.yaml \
  --debug

# Lint chart for errors
helm lint ./charts/myapp -f ./charts/myapp/values-dev.yaml
```

### Production

Production Helm usage emphasizes version pinning, atomic operations, and audit trails.

```bash
# Install from OCI registry with production values
helm install myapp ./charts/myapp \
  --version 0.3.0 \
  -f values-production.yaml \
  --namespace production \
  --create-namespace \
  --atomic \
  --timeout 10m \
  --wait

# Upgrade with atomic rollback on failure
helm upgrade myapp ./charts/myapp \
  --version 0.4.0 \
  -f values-production.yaml \
  --namespace production \
  --atomic \
  --timeout 10m

# Rollback to previous revision
helm rollback myapp 3 --namespace production

# View release history
helm history myapp --namespace production
```

The `--atomic` flag is essential for production: it automatically rolls back the entire release if any resource fails to become ready within the timeout. Without `--atomic`, a failed upgrade leaves the release in a partially-updated state.

## Performance

**Template rendering performance:** Complex charts with many conditionals and loops can be slow to render. Keep templates simple, avoid deeply nested `range` loops, and minimize the use of `include` within loops. For charts with 50+ templates, consider breaking them into sub-charts with clear boundaries.

**Release storage:** Helm stores release history as Kubernetes secrets (or configmaps) in the target namespace. Each revision stores the complete rendered manifests. Set `--history-max` on install/upgrade to limit the number of stored revisions (default is 10). Excessive history wastes etcd storage and slows `helm list` operations.

**Dependency resolution:** Run `helm dependency build` once and commit the `Chart.lock` file. In CI, use `helm dependency build` with a cache directory to avoid re-downloading charts on every pipeline run.

## Security

**Values validation:** Use `values.schema.json` to enforce required fields, type constraints, and enum values. This catches misconfigurations before they reach the cluster. Always require `resources.limits`, `image.repository`, and security-critical fields.

**Secrets in values:** Never store secrets directly in `values.yaml` files committed to Git. Use external secret management (Sealed Secrets, External Secrets Operator, SOPS) to encrypt secret values. Helmfile supports SOPS-encrypted values files natively via the `secrets:` key.

**Image policies:** Enforce image tag requirements in templates — reject `latest` tags and require digest-pinned images for production:
```yaml
{{- if and (eq .Values.image.pullPolicy "Always") (not .Values.image.tag) }}
{{- fail "image.tag is required when pullPolicy is Always" }}
{{- end }}
```

**RBAC:** Generate ServiceAccount, Role, and RoleBinding templates in charts. Default to least-privilege: no cluster-level permissions unless explicitly required.

## Testing

**Linting:**
```bash
# Basic lint
helm lint ./charts/myapp

# Lint with values
helm lint ./charts/myapp -f values-production.yaml

# Chart Testing (ct) for comprehensive validation
ct lint --charts ./charts/myapp --validate-maintainers=false
```

**Template rendering:**
```bash
# Render all templates
helm template myapp ./charts/myapp -f values.yaml

# Render specific template
helm template myapp ./charts/myapp -s templates/deployment.yaml

# Render with Kubernetes API validation
helm template myapp ./charts/myapp --validate
```

**Unit testing with helm-unittest:**
```yaml
# tests/deployment_test.yaml
suite: Deployment
templates:
  - deployment.yaml
tests:
  - it: should set correct replicas
    set:
      replicaCount: 3
    asserts:
      - equal:
          path: spec.replicas
          value: 3

  - it: should use appVersion as default image tag
    asserts:
      - matchRegex:
          path: spec.template.spec.containers[0].image
          pattern: ".*:1\\.2\\.3$"

  - it: should not set replicas when autoscaling is enabled
    set:
      autoscaling.enabled: true
    asserts:
      - isNull:
          path: spec.replicas
```

```bash
helm unittest ./charts/myapp
```

## Dos

- Use `values.schema.json` to validate chart values and catch misconfigurations before deployment.
- Use `--atomic` for production upgrades to auto-rollback on failure.
- Use library charts to share common template patterns (labels, security contexts) across charts.
- Use Helm hooks for database migrations and pre-deployment validation tasks.
- Store charts in OCI registries alongside container images for unified artifact management.
- Use Helmfile for multi-chart deployments with environment-specific overrides and release ordering.
- Pin chart versions in `Chart.yaml` dependencies and commit `Chart.lock`.
- Use `helm template` and `helm lint` in CI to validate charts before deployment.
- Include `helm test` pods for post-deployment smoke tests.

## Don'ts

- Do not store secrets in `values.yaml` files committed to version control — use Sealed Secrets, External Secrets, or SOPS.
- Do not use Helm 2 — Tiller is a security risk; Helm 3 eliminated it entirely.
- Do not use `helm install` without `--atomic` in production — partial failures leave releases in broken states.
- Do not hardcode image tags as `latest` in `values.yaml` — use specific versions or appVersion.
- Do not skip `values.schema.json` — unvalidated values cause silent deployment failures.
- Do not create charts with deeply nested template logic — extract complex logic into named templates in `_helpers.tpl`.
- Do not use `helm.sh/hook-delete-policy: hook-failed` alone — failed hook resources should be inspectable for debugging.
- Do not ignore `helm diff` (via Helmfile or plugin) before production upgrades — always review what will change.
