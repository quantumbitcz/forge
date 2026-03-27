# MicroK8s with Kubernetes

> Extends the K8s framework module with MicroK8s lightweight Kubernetes distribution patterns.
> Core Kubernetes conventions from `modules/frameworks/k8s/conventions.md` are NOT repeated here.

## Integration Setup

```bash
# Install MicroK8s via snap
sudo snap install microk8s --classic --channel=1.31/stable

# Join the microk8s group (avoid sudo for kubectl)
sudo usermod -aG microk8s $USER
newgrp microk8s

# Wait for ready
microk8s status --wait-ready

# Enable essential addons
microk8s enable dns storage helm3 registry
```

## Framework-Specific Patterns

### Addon Management

```bash
# Enable commonly needed addons
microk8s enable dns         # CoreDNS
microk8s enable storage     # Local storage provisioner
microk8s enable helm3       # Helm 3
microk8s enable registry    # Built-in container registry on localhost:32000
microk8s enable ingress     # nginx ingress controller
microk8s enable cert-manager  # TLS certificate management
microk8s enable observability # Prometheus + Grafana + Loki

# List enabled addons
microk8s status
```

MicroK8s addons are curated, tested combinations. Prefer addons over manual installations for consistency.

### Built-in Registry

```bash
# Enable the registry addon (runs on localhost:32000)
microk8s enable registry

# Tag and push images to the built-in registry
docker build -t localhost:32000/my-app:latest .
docker push localhost:32000/my-app:latest

# Reference in Kubernetes manifests
# image: localhost:32000/my-app:latest
```

### Helm Deployments

```bash
# Use MicroK8s's built-in Helm
microk8s helm3 repo add bitnami https://charts.bitnami.com/bitnami
microk8s helm3 install my-app charts/my-app \
  --namespace production \
  --create-namespace \
  --set image.repository=localhost:32000/my-app \
  --set image.tag=latest
```

### kubectl Alias

```bash
# MicroK8s bundles its own kubectl
microk8s kubectl get pods

# Or create an alias
alias kubectl='microk8s kubectl'

# Export kubeconfig for external tools
microk8s config > ~/.kube/config
```

### Multi-Node Cluster

```bash
# On the primary node
microk8s add-node
# Output: microk8s join <ip>:<port>/<token>

# On worker nodes
microk8s join <ip>:<port>/<token>

# Verify
microk8s kubectl get nodes
```

### Resource Limits for MicroK8s

```yaml
resources:
  requests:
    memory: 64Mi
    cpu: 50m
  limits:
    memory: 256Mi
    cpu: 500m
```

MicroK8s runs on resource-constrained hosts. Set realistic resource limits and avoid deploying resource-heavy workloads without accounting for MicroK8s overhead.

## Scaffolder Patterns

```yaml
patterns:
  addon_script: "scripts/setup-microk8s.sh"
```

## Additional Dos

- DO use MicroK8s addons for DNS, storage, and registry -- they're pre-tested combinations
- DO use the built-in registry (`localhost:32000`) for local development
- DO export kubeconfig with `microk8s config` for external tool compatibility
- DO enable `dns` and `storage` addons as a minimum baseline

## Additional Don'ts

- DON'T use `kubectl` directly without the `microk8s` prefix or alias -- it may point to a different cluster
- DON'T install addons manually when MicroK8s provides them -- use `microk8s enable`
- DON'T forget to add your user to the `microk8s` group -- commands fail without it
- DON'T deploy to MicroK8s in production without evaluating HA setup (`microk8s add-node`)
