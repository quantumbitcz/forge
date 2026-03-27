# Rancher with Kubernetes

> Extends `modules/container-orchestration/rancher.md` with Kubernetes multi-cluster management patterns.
> Generic Rancher conventions (cluster provisioning, RBAC, monitoring) are NOT repeated here.

## Integration Setup

```yaml
# fleet/fleet.yaml
defaultNamespace: production
helm:
  releaseName: my-app
  chart: charts/my-app
  valuesFiles:
    - values.yaml
targetCustomizations:
  - name: staging
    clusterSelector:
      matchLabels:
        env: staging
    helm:
      valuesFiles:
        - values-staging.yaml
  - name: production
    clusterSelector:
      matchLabels:
        env: production
    helm:
      valuesFiles:
        - values-production.yaml
```

## Framework-Specific Patterns

### Fleet GitOps Multi-Cluster Deployment

```yaml
# fleet/gitrepo.yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: infra-repo
  namespace: fleet-default
spec:
  repo: https://github.com/org/infra-repo.git
  branch: main
  paths:
    - charts/
  targets:
    - name: dev
      clusterSelector:
        matchLabels:
          env: dev
    - name: staging
      clusterSelector:
        matchLabels:
          env: staging
    - name: production
      clusterSelector:
        matchLabels:
          env: production
```

Fleet watches the Git repo and deploys to clusters matching the label selectors. Each cluster gets its own Helm release with environment-specific values.

### Rancher Apps Catalog

```yaml
# Deploy via Rancher Apps (Helm-based catalog)
apiVersion: catalog.cattle.io/v1
kind: ClusterRepo
metadata:
  name: org-charts
spec:
  url: https://charts.example.com
  gitRepo: https://github.com/org/helm-charts.git
  gitBranch: main
```

Rancher Apps extends Helm with a UI-driven install experience. Platform teams publish charts to the catalog; development teams install via the Rancher UI without needing `kubectl` access.

### Project-Level Resource Quotas

```yaml
# Enforce resource limits per Rancher project
apiVersion: management.cattle.io/v3
kind: Project
metadata:
  name: team-backend
spec:
  resourceQuota:
    limit:
      requestsCpu: "8"
      requestsMemory: 16Gi
      limitsCpu: "16"
      limitsMemory: 32Gi
  namespaceDefaultResourceQuota:
    limit:
      requestsCpu: "2"
      requestsMemory: 4Gi
```

### Continuous Delivery with Fleet Bundles

```yaml
# fleet/bundle.yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: Bundle
metadata:
  name: my-app
  namespace: fleet-default
spec:
  resources:
    - content: |
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: my-app
        spec:
          replicas: 2
  targets:
    - clusterSelector:
        matchLabels:
          env: production
```

## Scaffolder Patterns

```yaml
patterns:
  fleet_config: "fleet/fleet.yaml"
  gitrepo: "fleet/gitrepo.yaml"
```

## Additional Dos

- DO use Fleet for GitOps deployment across multiple clusters
- DO use `clusterSelector` labels for environment targeting
- DO use Rancher Apps catalog for self-service application deployment
- DO use project-level resource quotas to prevent noisy-neighbor problems

## Additional Don'ts

- DON'T manage individual cluster manifests manually -- use Fleet GitOps
- DON'T grant cluster-admin to development teams -- use Rancher's project-scoped RBAC
- DON'T bypass Fleet for ad-hoc `kubectl apply` -- it creates drift that Fleet cannot reconcile
- DON'T skip `targetCustomizations` -- deploying identical configs across environments causes failures
