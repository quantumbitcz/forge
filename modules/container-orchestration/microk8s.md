# MicroK8s

## Overview

MicroK8s is a lightweight, conformant Kubernetes distribution published by Canonical as a snap package. It provides a single-command installation, a modular addons system for enabling cluster features (DNS, storage, ingress, monitoring, GPU support, registry), and automatic security updates via snap's confinement and auto-refresh mechanism. MicroK8s is designed for developers, IoT deployments, edge computing, and small-scale production workloads.

Use MicroK8s when the team operates on Ubuntu or other snap-supporting Linux distributions and wants a Kubernetes installation that tracks upstream releases closely with automatic updates. MicroK8s excels at developer workstations (fast setup, low resource usage), CI/CD environments (snap-based reproducible installs), edge deployments (strict confinement, auto-updates), and GPU workloads (the `gpu` addon integrates NVIDIA device plugins with a single command). MicroK8s's addon system is its primary differentiator — enabling `dns`, `storage`, `ingress`, and `cert-manager` takes seconds rather than the minutes of manual Helm installations.

Do not use MicroK8s on platforms where snap is unavailable or unsupported (MacOS native, Windows native without WSL2, some container-optimized Linux distributions). Do not use MicroK8s for large-scale production clusters (50+ nodes) where managed Kubernetes services or enterprise distributions (OpenShift, Tanzu) provide better support SLAs and operational tooling. Do not use MicroK8s when the team needs to customize every cluster component — the addons system provides convenience at the cost of some configuration flexibility.

**MicroK8s vs. K3s comparison:**

| Feature | MicroK8s | K3s |
|---------|----------|-----|
| Installation method | Snap package | Single binary + install script |
| Platform support | Linux (snap), MacOS/Windows (VM) | Linux (native), MacOS/Windows (VM) |
| Auto-updates | Snap auto-refresh | System Upgrade Controller |
| Default CNI | Calico (via addon) | Flannel |
| Default storage | hostpath-storage (addon) | local-path-provisioner |
| Default ingress | Nginx (via addon) | Traefik |
| GPU support | Built-in addon | Manual NVIDIA device plugin |
| Datastore | Dqlite (distributed SQLite) | SQLite (single) or embedded etcd (HA) |
| Security model | Snap strict confinement | Standard Linux process |
| Registry | Built-in addon (local registry) | External registry required |
| ARM support | arm64 via snap | arm64 + armhf native |

## Architecture Patterns

### Installation and Addons System

MicroK8s installation is a single snap command. The addons system provides a curated set of pre-configured Kubernetes components that can be enabled and disabled with `microk8s enable` / `microk8s disable`.

**Installation:**
```bash
# Install MicroK8s (latest stable)
sudo snap install microk8s --classic --channel=1.31/stable

# Add current user to microk8s group (avoids sudo)
sudo usermod -a -G microk8s $USER
sudo chown -R $USER ~/.kube
newgrp microk8s

# Verify installation
microk8s status --wait-ready
microk8s kubectl get nodes
```

**Essential addons for development:**
```bash
# DNS — required for service discovery
microk8s enable dns

# Storage — local hostpath PersistentVolumes
microk8s enable hostpath-storage

# Ingress — nginx ingress controller
microk8s enable ingress

# Dashboard — Kubernetes web UI
microk8s enable dashboard

# Registry — local container image registry (localhost:32000)
microk8s enable registry

# Cert-manager — automatic TLS certificate management
microk8s enable cert-manager

# Metrics server — for HPA and resource metrics
microk8s enable metrics-server
```

**Production addons:**
```bash
# MetalLB — bare-metal load balancer
microk8s enable metallb:10.0.1.240-10.0.1.250

# GPU — NVIDIA device plugin and runtime
microk8s enable gpu

# Observability — Prometheus + Grafana + Loki stack
microk8s enable observability

# RBAC — role-based access control
microk8s enable rbac

# Community addons (via community repository)
microk8s enable community
microk8s enable argocd
microk8s enable portainer
microk8s enable traefik
```

**Custom addon configuration:**
```bash
# List available addons and their status
microk8s status

# Enable addon with arguments
microk8s enable metallb:192.168.1.240-192.168.1.250

# Disable an addon
microk8s disable dashboard

# Inspect addon manifests
ls /var/snap/microk8s/current/args/
```

### Clustering

MicroK8s supports multi-node clustering using Dqlite (Canonical's distributed SQLite), which provides high availability without requiring a separate etcd cluster. Clustering is initiated by generating a join token on an existing node and using it to add new nodes.

**Creating a cluster:**
```bash
# On the first node — generate join token
microk8s add-node

# Output:
# From the node you wish to join to this cluster, run the following:
# microk8s join 10.0.1.10:25000/abc123def456...

# On the second node — join the cluster
microk8s join 10.0.1.10:25000/abc123def456...

# On the first node again — generate another token for the third node
microk8s add-node

# On the third node
microk8s join 10.0.1.10:25000/ghi789jkl012...

# Verify cluster
microk8s kubectl get nodes
```

**Worker-only nodes:**
```bash
# Join as worker only (no control plane components)
microk8s join 10.0.1.10:25000/abc123def456... --worker
```

**Node removal:**
```bash
# From the leaving node
microk8s leave

# From any remaining node — remove the departed node
microk8s remove-node <node-name>
```

**Cluster status and diagnostics:**
```bash
# Cluster status
microk8s status

# Dqlite cluster membership
microk8s dbctl cluster

# Inspect running services
microk8s inspect
```

### Strict Confinement

MicroK8s can run in strict confinement mode, which uses snap's security sandbox to restrict the MicroK8s process's access to the host system. Strict confinement limits filesystem access, network capabilities, and system calls, providing defense-in-depth beyond Kubernetes's own security boundaries.

```bash
# Install with strict confinement
sudo snap install microk8s --channel=1.31-strict/stable

# Strict mode limitations:
# - No access to host filesystem outside snap directories
# - Cannot use hostPath volumes pointing to arbitrary host paths
# - Some addons may require additional snap connections
```

**Snap connections for strict mode:**
```bash
# Grant specific permissions if needed
sudo snap connect microk8s:hardware-observe
sudo snap connect microk8s:mount-observe
sudo snap connect microk8s:network-observe
sudo snap connect microk8s:log-observe
```

### Local Registry for Development

The built-in registry addon provides a container image registry at `localhost:32000`, eliminating the need for an external registry during development. This is particularly useful for inner-loop development where images are built and deployed locally.

```bash
# Enable the registry addon
microk8s enable registry

# Build and push an image
docker build -t localhost:32000/myapp:latest .
docker push localhost:32000/myapp:latest

# Use the image in Kubernetes manifests
# No imagePullSecrets required for localhost:32000
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: localhost:32000/myapp:latest
          ports:
            - containerPort: 8080
```

**Registry configuration for multi-node clusters:**
```bash
# Configure containerd to trust the registry on all nodes
# /var/snap/microk8s/current/args/containerd-template.toml
# Add registry mirror for cluster-wide access
```

## Configuration

### Development

Development configuration focuses on minimal resource usage and fast iteration.

```bash
# Install on developer machine
sudo snap install microk8s --classic --channel=1.31/stable

# Enable essential dev addons
microk8s enable dns hostpath-storage registry ingress

# Create alias for kubectl
sudo snap alias microk8s.kubectl kubectl
sudo snap alias microk8s.helm3 helm

# Set up kubeconfig for external tools
microk8s config > ~/.kube/config

# Deploy application
kubectl apply -f k8s/dev/

# Port-forward for local access
kubectl port-forward svc/myapp 8080:8080
```

**Resource reservation:**
```bash
# Configure MicroK8s resource limits (optional, for constrained machines)
sudo snap set microk8s config="
memory:
  request: 512Mi
  limit: 2Gi
"
```

### Production

Production configuration emphasizes high availability, monitoring, and security hardening.

```bash
# Install on all nodes (3 control plane + N workers)
sudo snap install microk8s --classic --channel=1.31/stable

# Enable production addons on the first node
microk8s enable dns
microk8s enable rbac
microk8s enable metrics-server
microk8s enable cert-manager
microk8s enable metallb:10.0.1.240-10.0.1.250
microk8s enable observability

# Create HA cluster
# (repeat add-node + join for each additional node)

# Pin snap channel to prevent unexpected upgrades
sudo snap refresh microk8s --channel=1.31/stable
sudo snap set system refresh.hold="2026-06-01T00:00:00Z"
```

**Auto-update configuration:**
```bash
# Control snap auto-refresh schedule
sudo snap set system refresh.timer=sat,4:00-7:00

# Hold auto-refresh for critical periods
sudo snap refresh --hold=48h microk8s

# Manual upgrade
sudo snap refresh microk8s --channel=1.32/stable
```

## Performance

**Dqlite performance:** MicroK8s uses Dqlite (distributed SQLite) as its default datastore. Dqlite provides lower memory usage than etcd (~50MB vs ~200MB) and performs well for clusters up to ~100 nodes and ~5000 pods. For larger clusters, performance may degrade as SQLite's write-ahead log grows — monitor Dqlite health via `microk8s dbctl cluster`.

**Addon overhead:** Each enabled addon consumes cluster resources. The observability addon (Prometheus + Grafana + Loki) alone can consume 2-4GB RAM. Enable only the addons the cluster actually needs. Use `microk8s status` to review enabled addons and disable unnecessary ones.

**Container runtime:** MicroK8s uses containerd as its container runtime. For build performance, the local registry addon avoids the latency of pulling images from remote registries. For runtime performance, ensure images are optimized (multi-stage builds, minimal base images) to reduce pull times and memory usage.

**Snap overhead:** The snap confinement layer adds a small amount of filesystem I/O overhead due to squashfs mounts. For I/O-intensive workloads, this overhead is negligible but measurable. Strict confinement adds slightly more overhead than classic confinement due to seccomp and AppArmor enforcement.

## Security

**RBAC:** Enable the `rbac` addon for production clusters. Without RBAC, any authenticated user has full cluster access. MicroK8s's default kubeconfig grants cluster-admin — create namespace-scoped service accounts and roles for application workloads.

```bash
microk8s enable rbac
```

**Network policies:** Enable the Calico-based CNI (default) to enforce NetworkPolicy resources. MicroK8s's Calico addon supports both Kubernetes NetworkPolicy and Calico-specific GlobalNetworkPolicy resources.

**Certificate management:**
```bash
# Enable cert-manager for automatic TLS
microk8s enable cert-manager

# Certificates are managed via cert-manager CRDs
# (ClusterIssuer, Certificate, etc.)
```

**Kubeconfig security:** The default kubeconfig generated by `microk8s config` contains cluster-admin credentials. In production, create limited RBAC users and distribute scoped kubeconfigs. Never share the default kubeconfig with application developers.

## Testing

**Addon verification:**
```bash
# Verify all addons are healthy
microk8s status --wait-ready

# Check specific addon deployment
microk8s kubectl get pods -n kube-system
microk8s kubectl get pods -n ingress
microk8s kubectl get pods -n observability

# DNS resolution test
microk8s kubectl run test --image=busybox:1.37 --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local
microk8s kubectl logs test
microk8s kubectl delete pod test
```

**Cluster diagnostics:**
```bash
# Comprehensive cluster inspection
microk8s inspect

# This generates a tarball with:
# - Node and pod status
# - Service logs (kubelet, containerd, apiserver)
# - Networking configuration
# - Addon status
# - Dqlite cluster health
```

**Integration testing in CI:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Install MicroK8s in CI runner
sudo snap install microk8s --classic --channel=1.31/stable
sudo microk8s enable dns hostpath-storage registry

# Wait for cluster
microk8s status --wait-ready

# Build and push test image
docker build -t localhost:32000/myapp:test .
docker push localhost:32000/myapp:test

# Deploy and test
microk8s kubectl apply -f k8s/test/
microk8s kubectl wait --for=condition=ready pod -l app=myapp --timeout=120s
microk8s kubectl port-forward svc/myapp 8080:8080 &
sleep 2
curl -sf http://localhost:8080/actuator/health

# Cleanup
microk8s kubectl delete -f k8s/test/
```

## Dos

- Use the addons system for standard components (DNS, storage, ingress, cert-manager) instead of manual Helm installations.
- Use Dqlite clustering with 3 control plane nodes for production high availability.
- Pin the snap channel in production and control auto-refresh scheduling to avoid unexpected upgrades during business hours.
- Enable RBAC for production clusters and create scoped service accounts for application workloads.
- Use the built-in registry addon for local development workflows to avoid external registry dependencies.
- Use `microk8s inspect` for comprehensive diagnostics when troubleshooting cluster issues.
- Enable the observability addon for production monitoring and alerting.
- Use strict confinement for security-sensitive edge deployments.

## Don'ts

- Do not use MicroK8s on platforms without snap support — the experience is degraded on non-Ubuntu Linux distributions without snap.
- Do not enable all addons by default — each addon consumes resources; enable only what the cluster needs.
- Do not use the default kubeconfig (cluster-admin) for application deployments — create namespace-scoped RBAC roles.
- Do not disable auto-refresh permanently in production — snap updates include security patches.
- Do not mix MicroK8s commands (`microk8s kubectl`) with system-installed kubectl without configuring the kubeconfig correctly — they may target different clusters.
- Do not use hostpath-storage addon for production stateful workloads that require data replication — install a proper CSI driver (OpenEBS, Longhorn).
- Do not skip DNS addon — it is required for service discovery and most Kubernetes features depend on it.
- Do not use strict confinement without testing all addons — some addons require additional snap connections that strict mode blocks by default.
