# K3s

## Overview

K3s is a lightweight, certified Kubernetes distribution built by Rancher Labs (now SUSE) for production workloads in resource-constrained environments. It packages the entire Kubernetes control plane into a single binary (~70MB), replaces etcd with SQLite (or embedded etcd for HA), bundles essential components (CoreDNS, Traefik ingress, local-path-provisioner, metrics-server, Flannel CNI), and removes legacy or alpha features that bloat upstream Kubernetes. K3s is a fully conformant Kubernetes distribution — any standard Kubernetes manifest, Helm chart, or operator works on K3s without modification.

Use K3s for edge computing, IoT gateways, CI/CD runners, development clusters, single-node production deployments, small team infrastructure (3-10 nodes), and any environment where the operational overhead of a full Kubernetes distribution (kubeadm, kops, or managed K8s) is disproportionate to the workload. K3s is particularly well-suited for self-hosted infrastructure on bare metal or small VMs where a managed Kubernetes service is not available or cost-effective. It is production-ready and runs real workloads at scale — it is not a toy or development-only tool.

Do not use K3s when the organization already has managed Kubernetes (EKS, GKE, AKS) infrastructure and the operational team is proficient with it — managed services provide better SLA guarantees, automated upgrades, and integrated monitoring. Do not use K3s when the workload requires features that K3s intentionally omits (cloud provider integrations, advanced storage CSI drivers that depend on cloud APIs). Do not use K3s as a drop-in replacement for full Kubernetes in air-gapped enterprise environments without understanding its networking defaults (Flannel + Traefik) and storage limitations (local-path only by default).

**K3s vs. MicroK8s vs. upstream Kubernetes:**

| Feature | K3s | MicroK8s | Upstream K8s |
|---------|-----|----------|-------------|
| Installation | Single binary, curl script | Snap package | kubeadm, kops, or managed |
| Binary size | ~70MB | ~200MB (snap) | Multiple binaries, GB total |
| Default datastore | SQLite (single), embedded etcd (HA) | Dqlite (Canonical's distributed SQLite) | etcd |
| Default CNI | Flannel (VXLAN) | Calico | User choice (Calico, Cilium, etc.) |
| Default ingress | Traefik v2 | Nginx (via addon) | None (user installs) |
| Default storage | local-path-provisioner | hostpath-storage (addon) | None (user installs CSI) |
| Auto-updates | System upgrade controller | Snap auto-refresh | Manual / managed service |
| HA mode | Embedded etcd (3+ servers) | Dqlite clustering | etcd cluster (3+ nodes) |
| Air-gap support | Yes (images tarball) | Yes (snap + images) | Yes (with effort) |
| ARM support | Native (arm64, armhf) | Via snap (arm64) | Via manifests |

## Architecture Patterns

### Installation and Cluster Setup

K3s installation is a single curl command that downloads the binary, configures systemd services, and optionally joins an existing cluster. The simplicity of installation is K3s's primary operational advantage — a production-ready cluster can be running in minutes rather than hours.

**Single-node installation:**
```bash
# Install K3s server (control plane + agent)
curl -sfL https://get.k3s.io | sh -

# Verify installation
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A

# Access kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
# Or copy to standard location:
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
```

**High-availability cluster (3 servers + N agents):**
```bash
# Server 1 — initializes the cluster with embedded etcd
curl -sfL https://get.k3s.io | sh -s - server \
  --cluster-init \
  --tls-san k3s.example.com \
  --tls-san 10.0.1.10

# Get the server token
sudo cat /var/lib/rancher/k3s/server/node-token

# Server 2, 3 — join the cluster
curl -sfL https://get.k3s.io | K3S_TOKEN="<token>" sh -s - server \
  --server https://10.0.1.10:6443 \
  --tls-san k3s.example.com

# Agent nodes — join as workers
curl -sfL https://get.k3s.io | K3S_URL=https://10.0.1.10:6443 \
  K3S_TOKEN="<token>" sh -s - agent
```

**Installation with configuration file (`/etc/rancher/k3s/config.yaml`):**
```yaml
# /etc/rancher/k3s/config.yaml
write-kubeconfig-mode: "0644"
tls-san:
  - k3s.example.com
  - 10.0.1.10
cluster-cidr: 10.42.0.0/16
service-cidr: 10.43.0.0/16
disable:
  - traefik           # Disable default Traefik if using custom ingress
  - servicelb         # Disable ServiceLB if using MetalLB
flannel-backend: wireguard-native  # WireGuard for encrypted pod networking
node-label:
  - environment=production
  - zone=us-east-1a
kubelet-arg:
  - max-pods=110
  - eviction-hard=memory.available<200Mi
```

### Traefik Default Ingress

K3s bundles Traefik v2 as its default ingress controller, deployed as a HelmChart custom resource managed by the K3s Helm controller. This means Traefik is installed and upgraded through K3s's built-in mechanism, not through a separate Helm installation.

**Customizing Traefik via HelmChartConfig:**
```yaml
# /var/lib/rancher/k3s/server/manifests/traefik-config.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    ports:
      web:
        redirectTo:
          entry_point: websecure
      websecure:
        tls:
          enabled: true
    additionalArguments:
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
    logs:
      general:
        level: WARN
      access:
        enabled: true
```

**IngressRoute (Traefik CRD) for advanced routing:**
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp
  namespace: myapp
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`myapp.example.com`)
      kind: Rule
      services:
        - name: myapp
          port: 8080
      middlewares:
        - name: rate-limit
        - name: compress
  tls:
    certResolver: letsencrypt
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
  namespace: myapp
spec:
  rateLimit:
    average: 100
    burst: 200
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: compress
  namespace: myapp
spec:
  compress: {}
```

**Replacing Traefik with nginx-ingress:**
```bash
# Disable Traefik at install time
curl -sfL https://get.k3s.io | sh -s - --disable traefik

# Or via config.yaml:
# disable:
#   - traefik

# Install nginx-ingress via Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-system --create-namespace
```

### Local-Path Provisioner and Storage

K3s bundles the Rancher local-path-provisioner as the default StorageClass, which creates PersistentVolumes backed by directories on the host filesystem. This works well for single-node clusters and development environments but requires careful consideration for production.

**Default StorageClass usage:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  namespace: database
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path   # K3s default
  resources:
    requests:
      storage: 10Gi
```

**Custom storage paths:**
```yaml
# /var/lib/rancher/k3s/server/manifests/local-storage-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-path-config
  namespace: kube-system
data:
  config.json: |-
    {
      "nodePathMap": [
        {
          "node": "DEFAULT_PATH_FOR_NON_LISTED_NODES",
          "paths": ["/opt/k3s-storage"]
        },
        {
          "node": "db-node-1",
          "paths": ["/mnt/ssd/k3s-storage"]
        }
      ]
    }
```

**Adding Longhorn for distributed storage:**
```bash
# Longhorn provides replicated, distributed block storage for K3s
helm repo add longhorn https://charts.longhorn.io
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system --create-namespace \
  --set defaultSettings.defaultReplicaCount=2

# Use Longhorn as StorageClass
kubectl patch storageclass longhorn -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl patch storageclass local-path -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

### Air-Gap Installation

K3s supports fully air-gapped installations where the target environment has no internet access. This is common in secure government environments, industrial edge locations, and regulated industries.

```bash
# On an internet-connected machine:

# 1. Download K3s binary
curl -Lo k3s https://github.com/k3s-io/k3s/releases/download/v1.31.4+k3s1/k3s
chmod +x k3s

# 2. Download container images
curl -Lo k3s-airgap-images.tar.zst \
  https://github.com/k3s-io/k3s/releases/download/v1.31.4+k3s1/k3s-airgap-images-amd64.tar.zst

# 3. Download install script
curl -Lo install.sh https://get.k3s.io

# Transfer to air-gapped machine, then:

# 4. Place binary
sudo cp k3s /usr/local/bin/k3s
sudo chmod +x /usr/local/bin/k3s

# 5. Place images
sudo mkdir -p /var/lib/rancher/k3s/agent/images/
sudo cp k3s-airgap-images.tar.zst /var/lib/rancher/k3s/agent/images/

# 6. Run install script in air-gap mode
INSTALL_K3S_SKIP_DOWNLOAD=true bash install.sh

# 7. For application images, use a private registry
# Configure K3s to use the private registry:
```

**Private registry configuration (`/etc/rancher/k3s/registries.yaml`):**
```yaml
mirrors:
  docker.io:
    endpoint:
      - "https://registry.internal.example.com"
  "registry.example.com":
    endpoint:
      - "https://registry.internal.example.com"

configs:
  "registry.internal.example.com":
    auth:
      username: admin
      password: secret
    tls:
      ca_file: /etc/ssl/certs/registry-ca.crt
```

## Configuration

### Development

Development K3s setup focuses on rapid iteration with a single-node cluster.

```bash
# Quick single-node development cluster
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --kube-apiserver-arg default-not-ready-toleration-seconds=10 \
  --kube-apiserver-arg default-unreachable-toleration-seconds=10

# Export kubeconfig for kubectl/helm
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Deploy application
kubectl apply -f k8s/dev/
```

### Production

Production K3s configuration emphasizes high availability, security hardening, and monitoring.

```yaml
# /etc/rancher/k3s/config.yaml (server nodes)
cluster-init: true
write-kubeconfig-mode: "0600"
tls-san:
  - k3s.example.com
  - 10.0.1.10
  - 10.0.1.11
  - 10.0.1.12

# Security hardening (CIS Benchmark)
protect-kernel-defaults: true
secrets-encryption: true
kube-apiserver-arg:
  - audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log
  - audit-policy-file=/etc/rancher/k3s/audit-policy.yaml
  - audit-log-maxage=30
  - audit-log-maxbackup=10
  - audit-log-maxsize=100
  - anonymous-auth=false
  - encryption-provider-config=/etc/rancher/k3s/encryption-config.yaml
kubelet-arg:
  - streaming-connection-idle-timeout=5m
  - make-iptables-util-chains=true
  - event-qps=0
  - protect-kernel-defaults=true

# Networking
flannel-backend: wireguard-native
cluster-cidr: 10.42.0.0/16
service-cidr: 10.43.0.0/16

# Auto-upgrades via System Upgrade Controller
# Deploy the SUC after cluster init
```

**Automated upgrades with System Upgrade Controller:**
```yaml
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: k3s-server
  namespace: system-upgrade
spec:
  concurrency: 1
  cordon: true
  nodeSelector:
    matchExpressions:
      - key: node-role.kubernetes.io/master
        operator: In
        values: ["true"]
  serviceAccountName: system-upgrade
  upgrade:
    image: rancher/k3s-upgrade
  channel: https://update.k3s.io/v1-release/channels/stable
---
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: k3s-agent
  namespace: system-upgrade
spec:
  concurrency: 2
  cordon: true
  nodeSelector:
    matchExpressions:
      - key: node-role.kubernetes.io/master
        operator: DoesNotExist
  prepare:
    args: ["prepare", "k3s-server"]
    image: rancher/k3s-upgrade
  serviceAccountName: system-upgrade
  upgrade:
    image: rancher/k3s-upgrade
  channel: https://update.k3s.io/v1-release/channels/stable
```

## Performance

**Resource usage:** K3s server nodes consume ~512MB RAM and minimal CPU for small clusters (10-20 pods). Agent nodes add ~256MB overhead. This is significantly less than upstream Kubernetes, which requires 2-4GB RAM for the control plane alone. For edge deployments on Raspberry Pi or similar devices, K3s is the only practical Kubernetes option.

**SQLite vs. embedded etcd:** SQLite is the default datastore for single-server installations. It is fast, requires zero configuration, and works well for small clusters (< 100 pods). For HA installations or clusters exceeding ~100 pods, use embedded etcd (`--cluster-init`) which provides distributed consensus and handles concurrent writes better. The switch from SQLite to embedded etcd is the single most impactful scaling decision.

**Flannel networking:** K3s uses Flannel with VXLAN as the default CNI. For performance-sensitive workloads, switch to WireGuard backend (`flannel-backend: wireguard-native`) which provides encrypted pod-to-pod networking with lower overhead than IPsec. For maximum networking performance, consider replacing Flannel with Cilium (eBPF-based, no encapsulation overhead).

## Security

**CIS Benchmark hardening:** K3s provides a CIS hardening guide specific to its distribution. Key hardening steps include enabling secrets encryption at rest, configuring audit logging, enabling `protect-kernel-defaults`, and running the `kube-bench` tool to validate compliance.

**Secrets encryption:**
```bash
# Enable at install time
curl -sfL https://get.k3s.io | sh -s - --secrets-encryption

# Verify
k3s secrets-encrypt status
```

**Network policies:** K3s supports Kubernetes NetworkPolicy resources when using a CNI that implements them. Flannel alone does not enforce network policies — install Calico or Cilium alongside Flannel for network policy enforcement, or replace Flannel entirely.

**Kubeconfig access:** The default kubeconfig at `/etc/rancher/k3s/k3s.yaml` is readable by root only. Set `--write-kubeconfig-mode 0600` explicitly in production. Never set `0644` in production — it allows any user on the host to access the cluster with admin privileges.

## Testing

**Cluster health verification:**
```bash
# Node status
kubectl get nodes -o wide

# System pod health
kubectl get pods -A

# Check K3s service status
systemctl status k3s

# Verify cluster networking
kubectl run test --image=busybox:1.37 --restart=Never -- \
  wget -qO- --timeout=5 kubernetes.default.svc.cluster.local
kubectl delete pod test

# Verify storage provisioner
kubectl get storageclass
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get pvc test-pvc
kubectl delete pvc test-pvc
```

**K3s-specific diagnostics:**
```bash
# K3s check-config (pre-installation validation)
curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true sh -
k3s check-config

# K3s etcd health (HA clusters)
k3s etcd-snapshot list
k3s etcd-snapshot save --name manual-backup

# Journal logs
journalctl -u k3s -f --no-pager
```

## Dos

- Use embedded etcd (`--cluster-init`) for HA production clusters with 3 server nodes.
- Pin K3s to a specific release channel (stable) and use the System Upgrade Controller for automated upgrades.
- Enable secrets encryption at rest for production clusters.
- Customize Traefik via HelmChartConfig rather than disabling and reinstalling separately.
- Use `/etc/rancher/k3s/config.yaml` for persistent configuration instead of command-line flags.
- Configure `registries.yaml` for private registries and air-gap environments.
- Use WireGuard Flannel backend for encrypted pod networking with minimal performance overhead.
- Take regular etcd snapshots (`k3s etcd-snapshot save`) and store them off-cluster.

## Don'ts

- Do not use SQLite for HA clusters — it does not support concurrent writes from multiple servers.
- Do not set `--write-kubeconfig-mode 0644` in production — it exposes cluster-admin access to all host users.
- Do not run without `--tls-san` for the API server's external hostname/IP — kubectl will fail TLS verification from remote machines.
- Do not skip CIS hardening steps (secrets encryption, audit logging, kernel defaults protection) for production deployments.
- Do not assume Flannel enforces NetworkPolicy — install Calico or Cilium for network policy enforcement.
- Do not use local-path-provisioner for stateful workloads that require replication — install Longhorn or an external CSI driver.
- Do not run K3s agent and server on the same node in HA clusters without understanding the resource implications — separate roles for production.
- Do not ignore the System Upgrade Controller — manual K3s upgrades across multiple nodes are error-prone.
