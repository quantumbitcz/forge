# K3s with Kubernetes

> Extends the K8s framework module with K3s lightweight Kubernetes distribution patterns.
> Core Kubernetes conventions from `modules/frameworks/k8s/conventions.md` are NOT repeated here.

## Integration Setup

```bash
# Single-node K3s installation
curl -sfL https://get.k3s.io | sh -

# With specific options
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable servicelb" sh -

# Access the cluster
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```

## Framework-Specific Patterns

### Local Development Cluster

```bash
# Install K3s for local development
curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" sh -s - \
  --disable traefik \
  --write-kubeconfig-mode 644

# Import local Docker images (no registry needed)
k3s ctr images import app.tar
```

K3s bundles containerd, so `docker` images must be imported via `ctr images import`. Alternatively, use a local registry.

### Local Registry

```bash
# Start a local registry
docker run -d --restart=always -p 5000:5000 --name registry registry:2

# Configure K3s to use the local registry
cat > /etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  "localhost:5000":
    endpoint:
      - "http://localhost:5000"
EOF

# Restart K3s to pick up registry config
sudo systemctl restart k3s
```

### Helm with K3s

```bash
# K3s includes a built-in Helm controller
# Deploy via HelmChart CRD:
cat <<EOF | kubectl apply -f -
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: my-app
  namespace: kube-system
spec:
  chart: my-app
  repo: https://charts.example.com
  targetNamespace: production
  valuesContent: |
    image:
      repository: registry.example.com/my-app
      tag: latest
    resources:
      limits:
        memory: 256Mi
EOF
```

K3s includes a Helm controller that watches `HelmChart` CRDs. No need to install Helm separately.

### Resource Limits for K3s

```yaml
# K3s runs on resource-constrained hosts -- set realistic limits
resources:
  requests:
    memory: 64Mi
    cpu: 50m
  limits:
    memory: 256Mi
    cpu: 500m
```

### Multi-Node K3s Cluster

```bash
# Server node
curl -sfL https://get.k3s.io | sh -

# Get the token
cat /var/lib/rancher/k3s/server/node-token

# Agent nodes
curl -sfL https://get.k3s.io | K3S_URL=https://server:6443 K3S_TOKEN=<token> sh -
```

## Scaffolder Patterns

```yaml
patterns:
  registries: "/etc/rancher/k3s/registries.yaml"
  helm_chart: "deploy/helmchart.yaml"
```

## Additional Dos

- DO disable Traefik and ServiceLB if you use your own ingress controller
- DO use K3s's built-in `HelmChart` CRD for simple deployments
- DO configure a local registry for development to avoid `ctr images import`
- DO set conservative resource limits -- K3s targets edge/resource-constrained hosts

## Additional Don'ts

- DON'T use `docker` commands to manage images in K3s -- it uses containerd
- DON'T assume K3s has the same defaults as upstream K8s (e.g., Traefik vs nginx-ingress)
- DON'T skip `registries.yaml` configuration for private registries
- DON'T deploy resource-heavy workloads without accounting for K3s overhead (~512MB)
