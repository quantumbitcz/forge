# Helm with Kubernetes

> Extends `modules/container-orchestration/helm.md` with Kubernetes-native Helm chart management patterns.
> Generic Helm conventions (chart structure, templating, release management) are NOT repeated here.

## Integration Setup

```bash
# Install a chart
helm install my-app ./charts/my-app \
  --namespace production \
  --create-namespace \
  --values values-production.yaml \
  --wait --timeout 300s

# Upgrade a release
helm upgrade my-app ./charts/my-app \
  --namespace production \
  --values values-production.yaml \
  --set image.tag=$(git rev-parse --short HEAD) \
  --wait --timeout 300s
```

## Framework-Specific Patterns

### Umbrella Chart for Multi-Service Deployments

```yaml
# Chart.yaml
apiVersion: v2
name: platform
version: 1.0.0
dependencies:
  - name: api
    version: "1.x.x"
    repository: "file://../api"
  - name: worker
    version: "1.x.x"
    repository: "file://../worker"
  - name: frontend
    version: "1.x.x"
    repository: "file://../frontend"
```

Umbrella charts group related services for atomic deployment. `helm dependency update` pulls sub-charts before install.

### Helm Hooks for Lifecycle Management

```yaml
# templates/pre-upgrade-migration.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-migrate
  annotations:
    helm.sh/hook: pre-install,pre-upgrade
    helm.sh/hook-delete-policy: before-hook-creation
    helm.sh/hook-weight: "-5"
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          command: ["migrate", "up"]
      restartPolicy: Never
  backoffLimit: 3
```

Hook weights control execution order. Negative weights run first. `before-hook-creation` deletes old hook resources before creating new ones.

### Values Schema Validation

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["image", "service"],
  "properties": {
    "image": {
      "type": "object",
      "required": ["repository", "tag"],
      "properties": {
        "repository": { "type": "string" },
        "tag": { "type": "string" }
      }
    },
    "service": {
      "type": "object",
      "properties": {
        "port": { "type": "integer", "minimum": 1, "maximum": 65535 }
      }
    }
  }
}
```

Place `values.schema.json` in the chart root. Helm validates values against this schema at install/upgrade time, catching misconfigurations early.

### OCI Registry Distribution

```bash
# Push chart to OCI registry
helm push my-app-1.0.0.tgz oci://registry.example.com/helm-charts

# Install from OCI registry
helm install my-app oci://registry.example.com/helm-charts/my-app --version 1.0.0
```

## Scaffolder Patterns

```yaml
patterns:
  chart: "charts/{name}/Chart.yaml"
  values: "charts/{name}/values.yaml"
  schema: "charts/{name}/values.schema.json"
```

## Additional Dos

- DO use `--wait` and `--timeout` for release status verification
- DO use `values.schema.json` for input validation
- DO use Helm hooks for database migrations and pre-deploy checks
- DO use OCI registries for chart distribution

## Additional Don'ts

- DON'T use `helm install` without `--namespace` -- it defaults to `default` namespace
- DON'T skip `--wait` in CI/CD -- without it, Helm reports success before pods are ready
- DON'T store secrets in `values.yaml` -- use External Secrets Operator or Sealed Secrets
- DON'T create charts without `values.schema.json` -- it prevents misconfiguration
