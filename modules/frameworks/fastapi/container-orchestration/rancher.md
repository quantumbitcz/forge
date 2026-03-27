# Rancher with FastAPI

> Extends `modules/container-orchestration/rancher.md` with FastAPI multi-cluster deployment patterns.
> Generic Rancher conventions (cluster provisioning, RBAC, monitoring) are NOT repeated here.

## Integration Setup

```yaml
# fleet/fleet.yaml
defaultNamespace: production
helm:
  releaseName: fastapi-app
  chart: charts/fastapi-app
  valuesFiles:
    - values.yaml
  values:
    image:
      repository: registry.example.com/fastapi-app
      tag: latest
    env:
      APP_ENV: production
      UVICORN_WORKERS: "4"
targetCustomizations:
  - name: staging
    clusterSelector:
      matchLabels:
        env: staging
    helm:
      valuesFiles:
        - values-staging.yaml
      values:
        env:
          UVICORN_WORKERS: "2"
```

## Framework-Specific Patterns

### Fleet GitOps for FastAPI

```yaml
# fleet/gitrepo.yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: fastapi-app
  namespace: fleet-default
spec:
  repo: https://github.com/org/fastapi-app.git
  branch: main
  paths:
    - deploy/charts/
  targets:
    - name: dev
      clusterSelector:
        matchLabels:
          env: dev
    - name: production
      clusterSelector:
        matchLabels:
          env: production
```

### Worker Scaling per Cluster

```yaml
# values-production.yaml
env:
  - name: APP_ENV
    value: production
  - name: UVICORN_WORKERS
    value: "4"
  - name: UVICORN_HOST
    value: "0.0.0.0"
  - name: UVICORN_PORT
    value: "8000"
resources:
  requests:
    memory: 256Mi
    cpu: 500m
  limits:
    memory: 512Mi
    cpu: "2"
```

Scale Uvicorn workers based on the cluster's CPU allocation. Use `2 * CPU_CORES + 1` as the baseline formula, but adjust based on workload profile (I/O-bound vs CPU-bound).

### Rancher Apps Catalog

```yaml
# Chart.yaml
apiVersion: v2
name: fastapi-app
version: 1.0.0
appVersion: "1.0.0"
annotations:
  catalog.cattle.io/display-name: FastAPI Application
  catalog.cattle.io/os: linux
```

### Database Migration as Fleet Pre-Hook

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
```

## Scaffolder Patterns

```yaml
patterns:
  fleet_config: "fleet/fleet.yaml"
  gitrepo: "fleet/gitrepo.yaml"
  values_prod: "deploy/charts/fastapi-app/values-production.yaml"
```

## Additional Dos

- DO scale `UVICORN_WORKERS` based on the cluster's CPU allocation
- DO use Alembic migrations as Helm pre-install hooks in Fleet deployments
- DO use Fleet `targetCustomizations` for environment-specific worker counts
- DO set `APP_ENV` per cluster to control FastAPI settings

## Additional Don'ts

- DON'T use the same worker count across clusters with different CPU limits
- DON'T hardcode database URLs -- use Kubernetes Secrets referenced in values
- DON'T skip health probes -- Fleet relies on them for deployment status
- DON'T deploy without running migrations first -- schema drift causes runtime errors
