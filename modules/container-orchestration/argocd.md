# ArgoCD

## Overview

ArgoCD is a declarative, GitOps-based continuous delivery tool for Kubernetes. It continuously monitors Git repositories containing Kubernetes manifests (plain YAML, Helm charts, Kustomize overlays, or Jsonnet) and reconciles the desired state defined in Git with the actual state in the target Kubernetes cluster. When drift is detected, ArgoCD can automatically sync the cluster to match Git, or alert operators for manual approval. ArgoCD is a CNCF graduated project and the most widely adopted GitOps tool for Kubernetes.

Use ArgoCD when the organization follows GitOps principles (Git as the single source of truth for cluster state), when deploying applications to one or more Kubernetes clusters, when needing audit trails for every deployment (Git commit history), and when requiring multi-environment promotion workflows (dev → staging → production). ArgoCD excels at managing the deployment side of CI/CD — it is not a CI tool (it does not build images or run tests) but rather a CD tool that deploys pre-built artifacts defined in Git.

Do not use ArgoCD for non-Kubernetes deployments — it is Kubernetes-native and has no support for VMs, serverless, or other deployment targets. Do not use ArgoCD as a CI system — it cannot build container images, run tests, or compile code; pair it with a CI system (GitHub Actions, GitLab CI, Jenkins, Tekton). Do not use ArgoCD for simple single-application deployments where `kubectl apply` or `helm upgrade` executed in a CI pipeline provides sufficient automation — ArgoCD adds operational complexity (its own deployment, RBAC, networking) that must be justified by the GitOps benefits.

Key differentiators: (1) The Application CRD provides a declarative way to define what should be deployed, where, and from which Git source. (2) ApplicationSet automates Application generation across clusters, environments, and repositories using generators (Git, Cluster, Matrix, Merge, Pull Request). (3) Sync strategies (auto/manual, with sync waves and sync windows) provide fine-grained control over when and how deployments happen. (4) The web UI provides real-time visualization of application health, sync status, resource trees, and diff views. (5) Multi-cluster support deploys to any Kubernetes cluster from a single ArgoCD instance. (6) SSO integration (OIDC, LDAP, SAML, GitHub, GitLab) provides enterprise authentication.

## Architecture Patterns

### App of Apps Pattern

The App of Apps pattern uses a root ArgoCD Application that manages child Applications, creating a hierarchical deployment structure. The root Application points to a Git directory containing Application manifests, and ArgoCD recursively syncs all child Applications. This pattern provides a single entry point for managing an entire cluster's application portfolio.

**Root Application:**
```yaml
# argocd/root-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/org/k8s-config.git
    targetRevision: main
    path: argocd/apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Child Application manifests (in `argocd/apps/`):**
```yaml
# argocd/apps/myapp.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: myapp-project
  source:
    repoURL: https://github.com/org/k8s-config.git
    targetRevision: main
    path: apps/myapp/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: myapp
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
---
# argocd/apps/monitoring.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring
  namespace: argocd
spec:
  project: infra
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 65.8.0
    helm:
      valuesObject:
        prometheus:
          prometheusSpec:
            retention: 30d
            storageSpec:
              volumeClaimTemplate:
                spec:
                  storageClassName: standard
                  resources:
                    requests:
                      storage: 50Gi
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

### ApplicationSet Generators

ApplicationSet automates the creation of ArgoCD Applications using generators that produce parameters from various sources. This eliminates the need to manually create Application manifests for each cluster, environment, or microservice.

**Git directory generator (one Application per directory):**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: microservices
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - git:
        repoURL: https://github.com/org/k8s-config.git
        revision: main
        directories:
          - path: "apps/*"
          - path: "apps/excluded-app"
            exclude: true
  template:
    metadata:
      name: "{{ .path.basename }}"
    spec:
      project: default
      source:
        repoURL: https://github.com/org/k8s-config.git
        targetRevision: main
        path: "{{ .path.path }}/overlays/production"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{ .path.basename }}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

**Cluster generator (deploy to all registered clusters):**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
  namespace: argocd
spec:
  goTemplate: true
  generators:
    - clusters:
        selector:
          matchLabels:
            environment: production
  template:
    metadata:
      name: "cluster-addons-{{ .name }}"
    spec:
      project: infra
      source:
        repoURL: https://github.com/org/k8s-config.git
        targetRevision: main
        path: cluster-addons
      destination:
        server: "{{ .server }}"
        namespace: kube-system
      syncPolicy:
        automated:
          selfHeal: true
```

**Matrix generator (cross-product of generators):**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: multi-cluster-apps
  namespace: argocd
spec:
  goTemplate: true
  generators:
    - matrix:
        generators:
          # Generator 1: clusters
          - clusters:
              selector:
                matchLabels:
                  environment: production
          # Generator 2: Git directories
          - git:
              repoURL: https://github.com/org/k8s-config.git
              revision: main
              directories:
                - path: "apps/*"
  template:
    metadata:
      name: "{{ .path.basename }}-{{ .name }}"
    spec:
      project: default
      source:
        repoURL: https://github.com/org/k8s-config.git
        targetRevision: main
        path: "{{ .path.path }}/overlays/{{ .metadata.labels.environment }}"
      destination:
        server: "{{ .server }}"
        namespace: "{{ .path.basename }}"
```

**Pull Request generator (preview environments):**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: preview-envs
  namespace: argocd
spec:
  goTemplate: true
  generators:
    - pullRequest:
        github:
          owner: org
          repo: myapp
          labels:
            - preview
        requeueAfterSeconds: 60
  template:
    metadata:
      name: "preview-{{ .number }}"
      annotations:
        argocd.argoproj.io/manifest-generate-paths: "."
    spec:
      project: preview
      source:
        repoURL: "https://github.com/org/myapp.git"
        targetRevision: "{{ .head_sha }}"
        path: k8s/preview
        helm:
          parameters:
            - name: image.tag
              value: "pr-{{ .number }}"
            - name: ingress.host
              value: "pr-{{ .number }}.preview.example.com"
      destination:
        server: https://kubernetes.default.svc
        namespace: "preview-{{ .number }}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

### Sync Strategies

ArgoCD provides fine-grained control over when and how applications are synced (deployed) through sync policies, sync waves, sync windows, and hook resources.

**Sync waves (ordered resource creation):**
```yaml
# Namespace first (wave -1)
apiVersion: v1
kind: Namespace
metadata:
  name: myapp
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
---
# ConfigMap/Secret before deployment (wave 0, default)
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-config
  annotations:
    argocd.argoproj.io/sync-wave: "0"
---
# Database migration job before app deployment (wave 1)
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
  annotations:
    argocd.argoproj.io/sync-wave: "1"
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
---
# Application deployment (wave 2)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  annotations:
    argocd.argoproj.io/sync-wave: "2"
---
# Ingress after deployment is ready (wave 3)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  annotations:
    argocd.argoproj.io/sync-wave: "3"
```

**Sync windows (maintenance windows):**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: production
  namespace: argocd
spec:
  syncWindows:
    # Allow syncs only during business hours on weekdays
    - kind: allow
      schedule: "0 9 * * 1-5"
      duration: 8h
      applications:
        - "*"
    # Deny syncs during weekend
    - kind: deny
      schedule: "0 0 * * 0,6"
      duration: 24h
      applications:
        - "*"
    # Emergency override — always allow infra apps
    - kind: allow
      schedule: "* * * * *"
      duration: 24h
      applications:
        - "infra-*"
```

**Auto-sync with self-healing:**
```yaml
syncPolicy:
  automated:
    prune: true      # Delete resources removed from Git
    selfHeal: true   # Revert manual changes (drift correction)
    allowEmpty: false # Prevent accidental deletion of all resources
  syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true              # Prune after all other syncs
    - RespectIgnoreDifferences=true
    - ServerSideApply=true        # Use server-side apply for CRDs
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 5m
```

### Secrets Management

ArgoCD does not handle secrets natively — it deploys whatever is in Git, which should never include plaintext secrets. The standard patterns use external secret management tools that integrate with ArgoCD's sync mechanism.

**Sealed Secrets (Bitnami):**
```yaml
# Encrypt secrets before committing to Git
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# ArgoCD syncs the SealedSecret, and the controller decrypts it
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: myapp-secrets
  namespace: myapp
spec:
  encryptedData:
    DB_PASSWORD: AgBy8hCq...base64...
    API_KEY: AgDz9kRt...base64...
```

**External Secrets Operator:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secrets
  namespace: myapp
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: aws-secrets-manager
  target:
    name: myapp-secrets
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: production/myapp
        property: db_password
    - secretKey: API_KEY
      remoteRef:
        key: production/myapp
        property: api_key
```

**SOPS with ArgoCD (via Helm secrets plugin):**
```bash
# Install Helm secrets plugin
helm plugin install https://github.com/jkroepke/helm-secrets

# Encrypt values file
sops --encrypt --in-place values-secrets.yaml
```

```yaml
# ArgoCD Application using SOPS-encrypted values
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    repoURL: https://github.com/org/k8s-config.git
    path: apps/myapp
    helm:
      valueFiles:
        - values.yaml
        - secrets+age-import:///helm-secrets-private-keys/key.txt?values-secrets.yaml
```

## Configuration

### Development

Development ArgoCD setup for testing GitOps workflows locally.

```bash
# Install ArgoCD on a local cluster (K3s, MicroK8s, kind)
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Get initial admin password
argocd admin initial-password -n argocd

# Port-forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login via CLI
argocd login localhost:8080 --insecure

# Add a Git repository
argocd repo add https://github.com/org/k8s-config.git

# Create an application
argocd app create myapp \
  --repo https://github.com/org/k8s-config.git \
  --path apps/myapp/overlays/dev \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace myapp \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

### Production

Production ArgoCD configuration emphasizes HA, SSO, and RBAC.

```yaml
# values-production.yaml (Helm chart installation)
# helm install argocd argo/argo-cd -f values-production.yaml -n argocd
server:
  replicas: 3
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 5
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts:
      - argocd.example.com
    tls:
      - secretName: argocd-tls
        hosts: [argocd.example.com]

controller:
  replicas: 2

repoServer:
  replicas: 3
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 5

applicationSet:
  replicas: 2

configs:
  params:
    server.insecure: false
    controller.diff.server.side: true
  cm:
    url: https://argocd.example.com
    dex.config: |
      connectors:
        - type: github
          id: github
          name: GitHub
          config:
            clientID: $dex-github:clientID
            clientSecret: $dex-github:clientSecret
            orgs:
              - name: org
  rbac:
    policy.csv: |
      p, role:readonly, applications, get, */*, allow
      p, role:developer, applications, sync, */*, allow
      p, role:developer, applications, get, */*, allow
      g, org:developers, role:developer
      g, org:platform, role:admin
    policy.default: role:readonly
```

## Performance

**Reconciliation performance:** ArgoCD's application controller reconciles each Application on a configurable interval (default 3 minutes). For clusters with hundreds of Applications, the controller can consume significant CPU and memory. Tune `--app-resync` and `--repo-server-timeout-seconds` based on cluster size. Enable sharding (`controller.replicas > 1` with shard assignment) for large-scale deployments.

**Repo server caching:** The repo server caches rendered manifests to avoid re-rendering on every reconciliation. Ensure the repo server has sufficient memory for the cache, especially when using Helm charts with large dependency trees.

**Webhook-driven sync:** Configure Git webhooks to trigger immediate sync rather than waiting for the polling interval. This reduces deployment latency from minutes to seconds:
```yaml
# Configure webhook in GitHub/GitLab to POST to:
# https://argocd.example.com/api/webhook
```

## Security

**RBAC:** ArgoCD provides fine-grained RBAC controlling who can view, sync, and manage Applications and Projects. Define policies in `argocd-rbac-cm` ConfigMap and map them to SSO groups.

**Project isolation:** Use ArgoCD Projects to isolate teams — each Project defines allowed source repositories, destination clusters/namespaces, and permitted resource kinds. This prevents one team from deploying to another team's namespace or using unauthorized source repositories.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-a
  namespace: argocd
spec:
  sourceRepos:
    - "https://github.com/org/team-a-*"
  destinations:
    - namespace: "team-a-*"
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
  namespaceResourceBlacklist:
    - group: ""
      kind: ResourceQuota
```

**Repository credentials:** Store Git repository credentials and Helm repository credentials as Kubernetes secrets in the `argocd` namespace. Never embed credentials in Application manifests.

## Testing

**Application sync testing:**
```bash
# Dry-run sync
argocd app sync myapp --dry-run

# Preview diff before sync
argocd app diff myapp

# Check application health
argocd app get myapp

# List all applications and their sync status
argocd app list

# Check for sync errors
argocd app get myapp --show-operation
```

**Manifest rendering validation:**
```bash
# Render manifests locally (same as ArgoCD would render)
argocd app manifests myapp --source live
argocd app manifests myapp --source git

# Compare live vs desired state
argocd app diff myapp --local ./apps/myapp
```

**ApplicationSet testing:**
```bash
# Preview generated Applications
kubectl get applicationsets -n argocd
kubectl describe applicationset microservices -n argocd

# Check generated Applications
argocd app list | grep microservices
```

## Dos

- Use the App of Apps pattern or ApplicationSets to manage Application definitions in Git, not manual `argocd app create` commands.
- Use sync waves to order resource creation (namespace → config → migration → deployment → ingress).
- Use sync windows to restrict production deployments to maintenance windows.
- Use ArgoCD Projects to isolate teams and enforce source repository and destination namespace boundaries.
- Use External Secrets Operator or Sealed Secrets for secret management — never commit plaintext secrets to Git.
- Configure Git webhooks for immediate sync on push, reducing deployment latency.
- Use `selfHeal: true` in production to detect and revert manual drift from the desired state in Git.
- Enable SSO (OIDC/SAML) and RBAC for production ArgoCD instances — never share the admin password.

## Don'ts

- Do not store plaintext secrets in Git repositories that ArgoCD syncs — use Sealed Secrets, External Secrets, or SOPS.
- Do not use `argocd app create` imperatively in production — define Applications in Git for auditability and reproducibility.
- Do not enable `prune: true` without `allowEmpty: false` — an empty Git directory would delete all resources in the namespace.
- Do not skip sync waves for applications with migration dependencies — database schemas must exist before the application starts.
- Do not grant the ArgoCD admin role to application developers — use RBAC to scope access to specific Projects.
- Do not use ArgoCD as a CI tool — it does not build images or run tests; pair it with a proper CI system.
- Do not run ArgoCD without HA in production — the controller is a single point of failure for deployment reconciliation.
- Do not configure auto-sync without self-heal — auto-sync without self-heal only catches Git changes, not manual drift.
