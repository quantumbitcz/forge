# Rancher

## Overview

Rancher is an open-source multi-cluster Kubernetes management platform by SUSE that provides a unified control plane for provisioning, managing, and monitoring Kubernetes clusters across any infrastructure — bare metal, on-premises VMs, and multiple cloud providers. It combines a web-based management UI, a centralized authentication system, cluster provisioning via RKE2 or K3s, GitOps-driven application deployment via Fleet, and an integrated monitoring/alerting stack based on Prometheus and Grafana.

Use Rancher when the organization manages multiple Kubernetes clusters across different environments (development, staging, production) and providers (AWS, Azure, bare metal, edge). Rancher is well-suited for platform teams that need to provide self-service Kubernetes access to development teams, enforce consistent security policies across clusters, and centralize monitoring and logging. Rancher's cluster provisioning capabilities (RKE2 for production, K3s for edge) make it the natural choice for organizations already using Rancher Labs distributions.

Do not use Rancher for single-cluster deployments where `kubectl` and Helm provide sufficient management. Do not use Rancher when the organization exclusively uses a single cloud provider's managed Kubernetes (EKS, GKE, AKS) — the cloud provider's native management tools are better integrated. Do not use Rancher when the team lacks the infrastructure to run Rancher's management server itself — Rancher adds operational overhead that must be justified by the multi-cluster management benefits.

Key differentiators: (1) Multi-cluster management from a single pane of glass — provision, upgrade, and monitor clusters across any infrastructure from one UI and API. (2) Fleet provides native GitOps-based application deployment across clusters at scale — a single Git repository can target hundreds of clusters with cluster-specific customizations. (3) Cluster provisioning supports RKE2 (hardened Kubernetes for production), K3s (lightweight for edge), and imported clusters (existing EKS/GKE/AKS clusters managed through Rancher). (4) Rancher Apps (catalog) extends Helm with curated application charts, lifecycle management, and multi-cluster deployment. (5) Centralized RBAC delegates cluster access control through Rancher's authentication proxy, integrating with LDAP, Active Directory, GitHub, and SAML providers.

## Architecture Patterns

### Multi-Cluster Management

Rancher operates as a management plane that runs on its own Kubernetes cluster (the "local" cluster) and manages "downstream" clusters. Downstream clusters can be provisioned by Rancher (RKE2, K3s, cloud-hosted) or imported (existing clusters that Rancher monitors and manages).

**Rancher installation (on dedicated management cluster):**
```bash
# Install Rancher via Helm on a K3s management cluster
# 1. Set up K3s management cluster
curl -sfL https://get.k3s.io | sh -s - --cluster-init

# 2. Install cert-manager (prerequisite)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml
kubectl wait --for=condition=Available -n cert-manager deployment/cert-manager --timeout=120s

# 3. Install Rancher
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.example.com \
  --set bootstrapPassword=admin \
  --set replicas=3 \
  --set ingress.tls.source=letsEncrypt \
  --set letsEncrypt.email=admin@example.com

# 4. Wait for deployment
kubectl -n cattle-system rollout status deployment/rancher
```

**Provisioning a downstream RKE2 cluster:**
```yaml
# Via Rancher API / UI:
# 1. Navigate to Cluster Management → Create
# 2. Select provider (Custom, AWS, Azure, vSphere)
# 3. Configure:
#    - Kubernetes version: v1.31.x
#    - CNI: Cilium or Calico
#    - Node pools: 3 control plane, 5 workers
#    - Enable monitoring, logging

# Via Rancher Terraform provider:
resource "rancher2_cluster_v2" "production" {
  name               = "production"
  kubernetes_version = "v1.31.4+rke2r1"

  rke_config {
    machine_pools {
      name                  = "control-plane"
      cloud_credential_name = rancher2_cloud_credential.aws.id
      control_plane_role    = true
      etcd_role             = true
      quantity              = 3

      machine_config {
        kind = rancher2_machine_config_v2.aws_cp.kind
        name = rancher2_machine_config_v2.aws_cp.name
      }
    }

    machine_pools {
      name                  = "workers"
      cloud_credential_name = rancher2_cloud_credential.aws.id
      worker_role           = true
      quantity              = 5

      machine_config {
        kind = rancher2_machine_config_v2.aws_worker.kind
        name = rancher2_machine_config_v2.aws_worker.name
      }
    }
  }
}
```

**Importing an existing cluster:**
```bash
# From Rancher UI: Cluster Management → Import Existing
# This generates a kubectl command to run on the target cluster:
kubectl apply -f https://rancher.example.com/v3/import/abc123def456.yaml

# Or via CLI:
rancher cluster import production-eks
```

### Fleet GitOps

Fleet is Rancher's built-in GitOps engine for deploying applications across multiple clusters from Git repositories. It scales to thousands of clusters and provides cluster-specific customizations via overlays, similar to Kustomize but with multi-cluster targeting built in.

**Fleet GitRepo configuration:**
```yaml
# fleet.yaml — deployed via Rancher's Fleet controller
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: myapp
  namespace: fleet-default
spec:
  repo: https://github.com/org/k8s-manifests.git
  branch: main
  paths:
    - /apps/myapp
  targets:
    - name: production
      clusterSelector:
        matchLabels:
          environment: production
    - name: staging
      clusterSelector:
        matchLabels:
          environment: staging
  pollingInterval: 30s
```

**Fleet bundle structure:**
```
k8s-manifests/
  apps/
    myapp/
      fleet.yaml              # Fleet configuration
      base/
        deployment.yaml
        service.yaml
        ingress.yaml
      overlays/
        production/
          kustomization.yaml  # Production-specific overrides
          patch-replicas.yaml
          patch-resources.yaml
        staging/
          kustomization.yaml  # Staging-specific overrides
```

**`fleet.yaml` with per-cluster customizations:**
```yaml
# apps/myapp/fleet.yaml
defaultNamespace: myapp
kustomize:
  dir: base

targetCustomizations:
  - name: production
    clusterSelector:
      matchLabels:
        environment: production
    kustomize:
      dir: overlays/production
    yaml:
      overlays:
        - inline:
            spec:
              template:
                metadata:
                  annotations:
                    cluster-autoscaler.kubernetes.io/safe-to-evict: "false"

  - name: staging
    clusterSelector:
      matchLabels:
        environment: staging
    kustomize:
      dir: overlays/staging
```

### Rancher Apps (Helm Catalog)

Rancher Apps extends Helm with a curated catalog of application charts, versioned lifecycle management, and multi-cluster deployment support. Charts can come from official Rancher repositories, Bitnami, or custom repositories.

```bash
# Add a custom Helm repository via Rancher
# UI: Apps → Repositories → Create

# Via kubectl:
cat <<EOF | kubectl apply -f -
apiVersion: catalog.cattle.io/v1
kind: ClusterRepo
metadata:
  name: company-charts
spec:
  url: https://charts.example.com
  gitRepo: https://github.com/org/helm-charts.git
  gitBranch: main
EOF
```

**Installing apps via Rancher:**
```bash
# From Rancher UI:
# 1. Select target cluster
# 2. Apps → Charts → Select chart
# 3. Configure values
# 4. Install

# Or via Helm against Rancher-managed cluster:
# Export kubeconfig for the downstream cluster from Rancher UI
export KUBECONFIG=~/.kube/production-cluster.yaml

helm install myapp company-charts/myapp \
  -f values-production.yaml \
  --namespace myapp --create-namespace
```

### Monitoring Stack

Rancher includes an integrated monitoring and alerting stack based on Prometheus, Grafana, and Alertmanager. It is installed as a Rancher App and pre-configured with dashboards for cluster health, node metrics, workload performance, and Kubernetes API server metrics.

```bash
# Enable monitoring via Rancher UI:
# Cluster → Monitoring → Install

# Or via Helm:
helm install rancher-monitoring rancher-charts/rancher-monitoring \
  --namespace cattle-monitoring-system \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.resources.requests.memory=2Gi \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.size=10Gi
```

**Custom ServiceMonitor for application metrics:**
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp
  namespace: myapp
  labels:
    release: rancher-monitoring
spec:
  selector:
    matchLabels:
      app: myapp
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 30s
```

**PrometheusRule for alerting:**
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: myapp-alerts
  namespace: myapp
  labels:
    release: rancher-monitoring
spec:
  groups:
    - name: myapp
      rules:
        - alert: HighErrorRate
          expr: |
            rate(http_server_requests_seconds_count{status=~"5..",app="myapp"}[5m])
            / rate(http_server_requests_seconds_count{app="myapp"}[5m]) > 0.05
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "High error rate on {{ $labels.instance }}"
            description: "Error rate is {{ $value | humanizePercentage }} for the last 5 minutes"
```

## Configuration

### Development

Development Rancher setup uses a minimal management cluster for testing multi-cluster workflows.

```bash
# Development management cluster (single-node K3s)
curl -sfL https://get.k3s.io | sh -

# Install Rancher with self-signed certificates
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.localhost \
  --set bootstrapPassword=admin \
  --set replicas=1 \
  --set ingress.tls.source=rancher

# Access Rancher UI
echo "https://rancher.localhost"
```

### Production

Production Rancher requires high availability, proper TLS, and backup.

```bash
# HA management cluster (3 K3s servers)
# Server 1:
curl -sfL https://get.k3s.io | sh -s - server --cluster-init \
  --tls-san rancher.example.com

# Server 2, 3:
curl -sfL https://get.k3s.io | K3S_TOKEN=<token> sh -s - server \
  --server https://10.0.1.10:6443

# Install Rancher with Let's Encrypt TLS
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.example.com \
  --set replicas=3 \
  --set ingress.tls.source=letsEncrypt \
  --set letsEncrypt.email=admin@example.com \
  --set auditLog.level=2 \
  --set auditLog.destination=hostPath

# Backup Rancher (rancher-backup operator)
helm install rancher-backup rancher-charts/rancher-backup \
  --namespace cattle-resources-system \
  --create-namespace
```

**Rancher backup schedule:**
```yaml
apiVersion: resources.cattle.io/v1
kind: Backup
metadata:
  name: daily-backup
spec:
  schedule: "0 2 * * *"
  retentionCount: 14
  resourceSetName: rancher-resource-set
  storageLocation:
    s3:
      bucketName: rancher-backups
      folder: daily
      region: us-east-1
      credentialSecretName: s3-creds
      credentialSecretNamespace: cattle-resources-system
```

## Performance

**Management cluster sizing:** The Rancher management server's resource requirements scale with the number of managed clusters and watched resources. For 5-10 clusters, 3 replicas with 2 CPU / 4GB RAM each is sufficient. For 50+ clusters, increase to 4 CPU / 8GB RAM per replica and monitor etcd performance on the management cluster.

**Fleet scaling:** Fleet is designed to manage thousands of clusters. However, each GitRepo that targets many clusters generates watch events proportional to the number of targets. Use cluster selectors and labels to scope GitRepos to relevant clusters rather than targeting all clusters with `matchExpressions: []`.

**Downstream cluster impact:** Rancher installs system agents on downstream clusters for management communication. These agents consume ~100MB RAM and minimal CPU per cluster. The impact is negligible for production workloads but should be accounted for on resource-constrained edge clusters.

## Security

**Authentication:** Rancher centralizes authentication for all managed clusters. Configure an external identity provider (LDAP, Active Directory, GitHub, SAML/OIDC) rather than using local Rancher accounts.

```bash
# Configure LDAP authentication via Rancher UI:
# Global Settings → Authentication → LDAP
# Or via API:
rancher login https://rancher.example.com --token <api-token>
```

**RBAC:** Rancher extends Kubernetes RBAC with Global Roles (Rancher-level), Cluster Roles (per-cluster), and Project Roles (per-namespace group). Use project roles to delegate namespace access to development teams without granting cluster-level permissions.

**CIS benchmarking:** Rancher includes a CIS benchmark scanning tool that evaluates downstream clusters against CIS Kubernetes Benchmark standards and generates compliance reports.

**Network isolation:** Use Rancher's project network isolation to restrict network traffic between namespaces grouped into different projects. This provides a lightweight alternative to Kubernetes NetworkPolicies for basic namespace isolation.

## Testing

**Rancher health verification:**
```bash
# Check Rancher pods
kubectl get pods -n cattle-system
kubectl get pods -n cattle-fleet-system

# Check downstream cluster connectivity
kubectl get clusters.management.cattle.io

# Verify Fleet controller
kubectl get gitrepos -A
kubectl get bundles -A

# Check monitoring stack
kubectl get pods -n cattle-monitoring-system
```

**Downstream cluster testing:**
```bash
# Switch context to downstream cluster (via Rancher UI kubeconfig download)
export KUBECONFIG=~/.kube/production.yaml

# Verify cluster health
kubectl get nodes
kubectl get pods -A
kubectl top nodes

# Test application deployment
kubectl apply -f test-deployment.yaml
kubectl rollout status deployment/test -n test
kubectl delete -f test-deployment.yaml
```

**Backup and restore testing:**
```bash
# Trigger manual backup
kubectl apply -f - <<EOF
apiVersion: resources.cattle.io/v1
kind: Backup
metadata:
  name: test-backup
spec:
  resourceSetName: rancher-resource-set
  storageLocation:
    s3:
      bucketName: rancher-backups
      folder: test
      region: us-east-1
      credentialSecretName: s3-creds
      credentialSecretNamespace: cattle-resources-system
EOF

# Verify backup
kubectl get backups
```

## Dos

- Run Rancher's management cluster with 3 replicas for high availability.
- Use Fleet for GitOps-based multi-cluster application deployment with cluster-specific customizations.
- Configure external authentication (LDAP, OIDC) rather than relying on local Rancher accounts.
- Use Rancher's project RBAC to delegate namespace access to development teams.
- Enable the rancher-backup operator and schedule regular backups to external storage.
- Label downstream clusters consistently (environment, region, team) for Fleet targeting and RBAC scoping.
- Use RKE2 for production downstream clusters and K3s for edge/development clusters.
- Monitor the management cluster's resource usage — it scales with the number of managed clusters.

## Don'ts

- Do not run Rancher management server as a single replica in production — loss of the management server prevents cluster management operations.
- Do not manage the Rancher management cluster through Rancher itself — use direct kubectl/Helm access for the local cluster.
- Do not use Rancher for single-cluster deployments where kubectl and Helm provide sufficient management.
- Do not grant Global Admin role broadly — use the least-privilege role (Cluster Member, Project Member) appropriate for each user.
- Do not skip backup configuration — Rancher stores cluster configurations, RBAC policies, and Fleet state that are costly to recreate.
- Do not use Fleet to target all clusters with a wildcard selector when only a subset needs the deployment — scope targets with labels.
- Do not ignore Rancher management cluster upgrades — running outdated Rancher versions may lack security patches and K8s version support.
- Do not store Rancher API tokens in Git or CI secrets without rotation policies — tokens provide full management access.
