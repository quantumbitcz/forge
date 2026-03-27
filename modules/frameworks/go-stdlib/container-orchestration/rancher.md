# Rancher with Go stdlib

> Extends `modules/container-orchestration/rancher.md` with Go stdlib multi-cluster deployment patterns.
> Generic Rancher conventions (cluster provisioning, RBAC, monitoring) are NOT repeated here.

## Integration Setup

```yaml
# fleet/fleet.yaml
defaultNamespace: production
helm:
  releaseName: go-app
  chart: charts/go-app
  valuesFiles:
    - values.yaml
  values:
    image:
      repository: registry.example.com/go-app
      tag: latest
targetCustomizations:
  - name: staging
    clusterSelector:
      matchLabels:
        env: staging
    helm:
      valuesFiles:
        - values-staging.yaml
```

## Framework-Specific Patterns

### Fleet GitOps for Go Services

```yaml
# fleet/gitrepo.yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: go-app
  namespace: fleet-default
spec:
  repo: https://github.com/org/go-app.git
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

### Minimal Resource Footprint

```yaml
# values-production.yaml
resources:
  requests:
    memory: 32Mi
    cpu: 50m
  limits:
    memory: 128Mi
    cpu: 500m
```

Go static binaries have minimal memory overhead. Set requests low and let the Go runtime adapt. `GOMEMLIMIT` can cap Go's heap to stay within the container limit.

### Environment-Specific Configuration

```yaml
# values-production.yaml
env:
  - name: APP_ENV
    value: production
  - name: GOMEMLIMIT
    value: 96MiB
  - name: GOMAXPROCS
    value: "2"
```

`GOMEMLIMIT` (Go 1.19+) soft-limits the heap. `GOMAXPROCS` should match the CPU limit to avoid throttling.

### Rancher Apps Catalog

```yaml
# Chart.yaml
apiVersion: v2
name: go-app
version: 1.0.0
appVersion: "1.0.0"
annotations:
  catalog.cattle.io/display-name: Go Application
  catalog.cattle.io/os: linux
```

## Scaffolder Patterns

```yaml
patterns:
  fleet_config: "fleet/fleet.yaml"
  gitrepo: "fleet/gitrepo.yaml"
```

## Additional Dos

- DO set `GOMEMLIMIT` to ~75% of the container memory limit
- DO set `GOMAXPROCS` to match the CPU limit
- DO use `scratch` base image -- Go static binaries have no runtime dependencies
- DO use Fleet `clusterSelector` for multi-cluster targeting

## Additional Don'ts

- DON'T over-provision memory -- Go services are memory-efficient
- DON'T skip `GOMEMLIMIT` -- without it, Go's GC may trigger OOM kills
- DON'T use the same `GOMAXPROCS` across clusters with different CPU limits
- DON'T bypass Fleet for manual deployments -- it creates unreconcilable drift
