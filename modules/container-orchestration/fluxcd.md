# FluxCD

## Overview

FluxCD (Flux v2) is a CNCF graduated GitOps toolkit for Kubernetes that keeps clusters in sync with sources of configuration (Git repositories, Helm repositories, OCI registries, S3 buckets). Unlike monolithic GitOps tools, Flux is built as a set of composable, single-purpose controllers — each handling one concern (source retrieval, Kustomize rendering, Helm release management, image automation, notifications). These controllers are Kubernetes-native custom resources that can be used independently or combined for complex workflows.

Use FluxCD when the organization wants a Kubernetes-native GitOps solution that integrates deeply with the Kubernetes API rather than providing a separate UI and API layer. Flux excels in multi-tenant environments where different teams manage their own namespaces with independent Git sources, in environments where Kustomize is the primary manifest management tool, and in automated image update workflows where Flux can detect new container image tags and automatically commit updated manifests to Git. Flux's controller-based architecture makes it lightweight and modular — install only the controllers you need.

Do not use FluxCD when the team requires a rich web UI for deployment visualization — Flux's UI (Weave GitOps) is less mature than ArgoCD's built-in dashboard. Do not use FluxCD when the team is unfamiliar with Kubernetes custom resources — Flux's CRD-based configuration has a steeper learning curve than ArgoCD's CLI and UI-driven workflows. Do not use FluxCD for non-Kubernetes deployments.

**FluxCD vs. ArgoCD comparison:**

| Feature | FluxCD | ArgoCD |
|---------|--------|--------|
| Architecture | Set of controllers (CRDs) | Monolithic application |
| UI | Weave GitOps (separate) | Built-in web UI |
| Manifest tools | Kustomize (native), Helm | Kustomize, Helm, Jsonnet, plain YAML |
| Image automation | Built-in controller | External (Argo Image Updater) |
| Multi-tenancy | Namespace-scoped by design | Project-based isolation |
| Notification | Built-in controller (Slack, Teams, etc.) | Webhook-based |
| Sync mechanism | Pull-based reconciliation | Pull-based + webhook trigger |
| Secret management | SOPS (built-in), Sealed Secrets | External (Sealed Secrets, ESO) |
| Bootstrap | `flux bootstrap` (one command) | Helm install or manifests |
| Multi-cluster | Via Kustomization targeting | Built-in cluster management |
| Drift detection | Continuous, per-controller | Periodic reconciliation |

## Architecture Patterns

### Core CRDs and Controllers

Flux v2 consists of specialized controllers, each managing a specific CRD. Understanding these CRDs is essential for configuring Flux deployments.

**Source Controller** manages source artifacts:
```yaml
# GitRepository — tracks a Git repository branch or tag
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: myapp
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/org/k8s-config.git
  ref:
    branch: main
  secretRef:
    name: git-credentials
  ignore: |
    # Ignore non-manifests
    *.md
    .github/
---
# HelmRepository — tracks a Helm chart repository
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: bitnami
  namespace: flux-system
spec:
  interval: 30m
  url: https://charts.bitnami.com/bitnami
  type: default   # or "oci" for OCI registries
---
# OCIRepository — tracks OCI artifacts (charts, manifests)
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: OCIRepository
metadata:
  name: myapp-manifests
  namespace: flux-system
spec:
  interval: 5m
  url: oci://registry.example.com/manifests/myapp
  ref:
    tag: latest
```

**Kustomize Controller** applies Kustomize overlays:
```yaml
# Kustomization — reconciles manifests from a GitRepository
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: myapp
  namespace: flux-system
spec:
  interval: 5m
  targetNamespace: myapp
  sourceRef:
    kind: GitRepository
    name: myapp
  path: ./apps/myapp/overlays/production
  prune: true
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: myapp
      namespace: myapp
  timeout: 5m
  dependsOn:
    - name: infrastructure
  postBuild:
    substitute:
      CLUSTER_NAME: production-us-east
      DOMAIN: example.com
    substituteFrom:
      - kind: ConfigMap
        name: cluster-vars
      - kind: Secret
        name: cluster-secrets
```

**Helm Controller** manages Helm releases:
```yaml
# HelmRelease — installs/upgrades a Helm chart
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: myapp
  namespace: myapp
spec:
  interval: 10m
  chart:
    spec:
      chart: myapp
      version: ">=1.0.0 <2.0.0"   # Semver range
      sourceRef:
        kind: HelmRepository
        name: company-charts
        namespace: flux-system
  values:
    replicaCount: 3
    image:
      repository: registry.example.com/myapp
      tag: 1.2.3
    resources:
      limits:
        cpu: "2"
        memory: 1Gi
      requests:
        cpu: 500m
        memory: 512Mi
    ingress:
      enabled: true
      className: nginx
      hosts:
        - host: myapp.example.com
          paths:
            - path: /
              pathType: Prefix
  valuesFrom:
    - kind: ConfigMap
      name: myapp-values
      valuesKey: extra-values.yaml
    - kind: Secret
      name: myapp-secrets
      valuesKey: secret-values.yaml
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true
  rollback:
    cleanupOnFail: true
  test:
    enable: true
```

### GitOps Repository Structure

Flux projects typically use a monorepo structure with Kustomize overlays for environment-specific configuration. The directory layout separates infrastructure components from application deployments and uses Kustomize dependencies to control deployment ordering.

**Standard Flux repository structure:**
```
k8s-config/
  clusters/
    production/
      flux-system/              # Flux bootstrap (auto-generated)
        gotk-components.yaml
        gotk-sync.yaml
        kustomization.yaml
      infrastructure.yaml       # Kustomization pointing to infrastructure/
      apps.yaml                 # Kustomization pointing to apps/
    staging/
      flux-system/
      infrastructure.yaml
      apps.yaml

  infrastructure/
    controllers/
      ingress-nginx/
        helmrelease.yaml
        kustomization.yaml
      cert-manager/
        helmrelease.yaml
        kustomization.yaml
      kustomization.yaml
    configs/
      cluster-issuer.yaml
      kustomization.yaml
    kustomization.yaml

  apps/
    base/
      myapp/
        namespace.yaml
        deployment.yaml
        service.yaml
        ingress.yaml
        kustomization.yaml
      kustomization.yaml
    production/
      myapp/
        kustomization.yaml     # Patches for production
        patch-replicas.yaml
        patch-resources.yaml
      kustomization.yaml
    staging/
      myapp/
        kustomization.yaml     # Patches for staging
      kustomization.yaml
```

**Cluster entry point (`clusters/production/infrastructure.yaml`):**
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure
  prune: true
  wait: true
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-configs
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/configs
  prune: true
  dependsOn:
    - name: infrastructure
```

**Cluster entry point (`clusters/production/apps.yaml`):**
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./apps/production
  prune: true
  dependsOn:
    - name: infrastructure
    - name: infrastructure-configs
```

### Image Automation

Flux's image automation controllers can detect new container image tags in registries and automatically update Kustomize or plain YAML manifests in Git, committing the changes back. This creates a fully automated CI/CD pipeline: CI builds and pushes a new image tag, Flux detects it, updates the manifest in Git, and then reconciles the cluster.

**Image automation components:**
```yaml
# ImageRepository — scans a container registry for tags
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: myapp
  namespace: flux-system
spec:
  image: registry.example.com/myapp
  interval: 5m
  secretRef:
    name: registry-credentials
---
# ImagePolicy — selects which tag to use
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: myapp
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: myapp
  policy:
    semver:
      range: ">=1.0.0"
---
# ImageUpdateAutomation — commits tag updates to Git
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageUpdateAutomation
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 30m
  sourceRef:
    kind: GitRepository
    name: flux-system
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        name: fluxcdbot
        email: fluxcd@example.com
      messageTemplate: |
        chore: update images

        Automation: {{ range .Changed.Changes }}
        - {{ .OldValue }} -> {{ .NewValue }}
        {{ end }}
    push:
      branch: main
  update:
    path: ./apps
    strategy: Setters
```

**Marking manifests for image updates:**
```yaml
# In deployment.yaml, add image policy markers:
containers:
  - name: myapp
    image: registry.example.com/myapp:1.2.3 # {"$imagepolicy": "flux-system:myapp"}
```

When Flux detects a new image tag matching the ImagePolicy (e.g., `1.3.0`), it updates the tagged line in Git, commits, and pushes. The GitRepository source detects the new commit and reconciles the cluster.

### Notification Controller

Flux's notification controller sends alerts about reconciliation events (successful syncs, failures, health check changes) to external services (Slack, Microsoft Teams, GitHub, GitLab, PagerDuty, webhooks).

```yaml
# Provider — defines where to send notifications
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: slack
  namespace: flux-system
spec:
  type: slack
  channel: deployments
  secretRef:
    name: slack-webhook
---
# Alert — defines what triggers notifications
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: deployment-alerts
  namespace: flux-system
spec:
  providerRef:
    name: slack
  eventSeverity: info
  eventSources:
    - kind: Kustomization
      name: "*"
    - kind: HelmRelease
      name: "*"
  exclusionList:
    - ".*no new revision.*"
---
# Receiver — accepts webhooks from external systems (GitHub, GitLab)
apiVersion: notification.toolkit.fluxcd.io/v1
kind: Receiver
metadata:
  name: github-webhook
  namespace: flux-system
spec:
  type: github
  events:
    - "ping"
    - "push"
  secretRef:
    name: webhook-token
  resources:
    - kind: GitRepository
      name: myapp
```

## Configuration

### Development

Development Flux setup for testing GitOps workflows locally.

```bash
# Bootstrap Flux on a local cluster
flux bootstrap github \
  --owner=org \
  --repository=k8s-config \
  --branch=main \
  --path=clusters/dev \
  --personal

# Check Flux status
flux check

# Watch reconciliation
flux get kustomizations --watch

# Trigger manual reconciliation
flux reconcile kustomization apps --with-source

# Suspend reconciliation during development
flux suspend kustomization myapp
# ... make manual changes ...
flux resume kustomization myapp
```

### Production

Production Flux configuration emphasizes multi-cluster support, SOPS encryption, and health monitoring.

```bash
# Bootstrap Flux with SOPS decryption
flux bootstrap github \
  --owner=org \
  --repository=k8s-config \
  --branch=main \
  --path=clusters/production \
  --components-extra=image-reflector-controller,image-automation-controller

# Configure SOPS decryption
# Create age key secret
cat age.agekey | kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/dev/stdin

# Configure Kustomization to use SOPS
```

```yaml
# Kustomization with SOPS decryption
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./apps/production
  prune: true
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

**Multi-cluster with shared repository:**
```yaml
# Each cluster has its own path in the same repository
# clusters/production-us-east/flux-system/kustomization.yaml
# clusters/production-eu-west/flux-system/kustomization.yaml
# Shared infrastructure and app bases, cluster-specific overlays
```

## Performance

**Reconciliation intervals:** Each Flux resource has an `interval` that controls how often it checks for changes. Set shorter intervals (1-5m) for application Kustomizations and longer intervals (10-30m) for infrastructure and Helm repositories. Overly short intervals increase API server load and Git provider rate limiting.

**Source caching:** The source controller caches downloaded artifacts (Git clones, Helm chart tarballs) and only re-downloads when the source revision changes. This minimizes bandwidth usage and Git provider load.

**Kustomize rendering:** Large Kustomize overlays with many resources can be slow to render. The Kustomize controller runs in-process rendering — for very large manifests, increase the controller's memory limit. Use `dependsOn` to break large Kustomizations into smaller, independently-reconciled units.

**Helm release performance:** HelmRelease reconciliation includes template rendering, diff computation, and Helm upgrade execution. For charts with hundreds of resources, the upgrade process can take minutes. Set appropriate `timeout` values and use `spec.upgrade.remediation.retries` to handle transient failures.

## Security

**SOPS integration:** Flux has built-in SOPS decryption support in the Kustomize controller. Encrypt secret manifests with SOPS (using age, PGP, or cloud KMS) and commit them to Git. Flux decrypts them at reconciliation time without persisting plaintext to disk.

```bash
# Encrypt a secret with SOPS + age
sops --age=age1... --encrypt --in-place secret.yaml

# Flux decrypts automatically when configured with decryption provider
```

**Multi-tenancy:** Flux supports namespace-scoped tenancy where each team manages its own GitRepository and Kustomization resources in their namespace. The Flux controllers enforce that a tenant's Kustomization can only target resources in namespaces it has access to, preventing cross-tenant interference.

```yaml
# Tenant configuration
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: team-a-apps
  namespace: team-a
spec:
  serviceAccountName: team-a-reconciler  # Scoped RBAC
  sourceRef:
    kind: GitRepository
    name: team-a-repo
    namespace: team-a
  path: ./apps
  targetNamespace: team-a
  prune: true
```

**Service account isolation:** Use `spec.serviceAccountName` on Kustomizations to run reconciliation with a scoped Kubernetes service account, limiting what resources the reconciliation can create, update, or delete.

**Network policies:** Apply network policies to the `flux-system` namespace to restrict the source controller's outbound traffic to only approved Git hosts and registries.

## Testing

**Flux installation verification:**
```bash
# Comprehensive pre-check
flux check --pre

# Post-install verification
flux check

# View all Flux resources and their status
flux get all -A

# Check source reconciliation
flux get sources git -A
flux get sources helm -A

# Check Kustomization status
flux get kustomizations -A

# Check HelmRelease status
flux get helmreleases -A
```

**Troubleshooting:**
```bash
# View Flux controller logs
flux logs --all-namespaces

# View specific controller logs
kubectl logs -n flux-system deployment/source-controller -f
kubectl logs -n flux-system deployment/kustomize-controller -f
kubectl logs -n flux-system deployment/helm-controller -f

# Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization apps --with-source

# Inspect events
kubectl events -n flux-system --for Kustomization/apps
```

**Dry-run validation:**
```bash
# Validate Kustomize overlays locally
kustomize build apps/production/myapp

# Validate HelmRelease values
helm template myapp ./charts/myapp -f values-production.yaml

# Export Flux resources for review
flux export source git --all > sources.yaml
flux export kustomization --all > kustomizations.yaml
```

## Dos

- Use `dependsOn` to establish deployment ordering (infrastructure before configs before applications).
- Use SOPS with age keys for encrypting secrets in Git — it is built into Flux's Kustomize controller.
- Use Image Automation for fully automated CI/CD pipelines (CI pushes image, Flux updates manifest and deploys).
- Use the notification controller to send deployment alerts to Slack, Teams, or PagerDuty.
- Use `prune: true` on Kustomizations to ensure deleted resources in Git are removed from the cluster.
- Use health checks on Kustomizations to verify deployment readiness before dependent Kustomizations proceed.
- Use namespace-scoped service accounts for multi-tenant reconciliation to enforce RBAC boundaries.
- Structure repositories with clear separation between infrastructure, configs, and applications.

## Don'ts

- Do not set reconciliation intervals shorter than 1 minute for Git sources — this causes excessive Git provider load and potential rate limiting.
- Do not commit plaintext secrets to Git — always use SOPS encryption or External Secrets.
- Do not use `prune: true` without health checks — Flux might prune resources before replacements are healthy.
- Do not mix Flux and manual `kubectl apply` for the same resources — Flux will revert manual changes (that is its purpose).
- Do not install all Flux controllers if only a subset is needed — install only the controllers the deployment requires.
- Do not ignore `flux check` warnings — they indicate configuration or compatibility issues that can cause reconciliation failures.
- Do not use `spec.force: true` on Kustomizations without understanding the implications — it recreates resources instead of patching, causing downtime.
- Do not skip the notification controller in production — deployment failures should trigger alerts, not go unnoticed until users report issues.
