# OpenShift

## Overview

OpenShift is Red Hat's enterprise Kubernetes platform that extends upstream Kubernetes with developer tooling, operational automation, built-in CI/CD, enhanced security defaults, and enterprise support. It adds an opinionated layer on top of Kubernetes that includes Routes (a higher-level ingress abstraction), Security Context Constraints (SCCs — more granular than PodSecurityPolicies), BuildConfig/ImageStream (built-in CI/CD for container images), OperatorHub (a marketplace of pre-packaged operators), and the `oc` CLI (a superset of `kubectl` with OpenShift-specific commands).

Use OpenShift when the organization requires enterprise support, regulatory compliance (FedRAMP, HIPAA, PCI-DSS), integrated developer experience (source-to-image builds, integrated CI/CD, web console), and a hardened-by-default Kubernetes platform. OpenShift is well-suited for large enterprises with dedicated platform teams, regulated industries that need certifiable Kubernetes distributions, and organizations that want a unified platform spanning bare metal, VMware, and multiple cloud providers (AWS, Azure, GCP).

Do not use OpenShift for small projects or startups where managed Kubernetes (EKS, GKE, AKS) provides sufficient capabilities at lower cost. Do not use OpenShift when the team does not need its enterprise features — the additional operational complexity and licensing cost are not justified for simple deployments. Do not use OpenShift-specific features (DeploymentConfig, BuildConfig, ImageStream) for new projects when standard Kubernetes equivalents exist — prefer Deployments over DeploymentConfigs, Helm/ArgoCD over BuildConfig, and OCI registries over ImageStreams, while understanding that some legacy OpenShift-specific features are being deprecated in favor of their upstream Kubernetes counterparts.

Key differentiators from standard Kubernetes: (1) Security-by-default: OpenShift runs all containers as non-root by default via the restricted SCC, which upstream Kubernetes does not enforce. (2) Routes provide TLS termination, path-based routing, and A/B deployment natively without requiring an ingress controller installation. (3) The web console provides developer-centric views (topology, builds, pipelines) alongside admin views. (4) OperatorHub provides a curated catalog of certified operators with lifecycle management. (5) OpenShift Pipelines (Tekton) and OpenShift GitOps (ArgoCD) are pre-integrated and supported by Red Hat.

## Architecture Patterns

### Routes vs. Ingress

OpenShift Routes are the platform's native ingress mechanism, predating Kubernetes Ingress and providing features that standard Ingress objects require annotations or custom resources to achieve. Routes are implemented by the OpenShift Router (HAProxy-based) and support TLS termination (edge, passthrough, re-encrypt), weighted traffic splitting for canary deployments, and path-based routing.

**Route examples:**
```yaml
# Edge TLS termination (Router terminates TLS, forwards HTTP to pod)
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: myapp
  namespace: myapp
spec:
  host: myapp.apps.cluster.example.com
  to:
    kind: Service
    name: myapp
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
---
# Passthrough TLS (Router forwards encrypted traffic to pod)
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: myapp-secure
  namespace: myapp
spec:
  host: secure.apps.cluster.example.com
  to:
    kind: Service
    name: myapp
  tls:
    termination: passthrough
---
# Weighted routing for canary deployments
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: myapp-canary
  namespace: myapp
spec:
  host: myapp.apps.cluster.example.com
  to:
    kind: Service
    name: myapp-stable
    weight: 90
  alternateBackends:
    - kind: Service
      name: myapp-canary
      weight: 10
  tls:
    termination: edge
```

**When to use Routes vs. Ingress:** Use Routes when deploying on OpenShift and the application needs TLS termination, weighted traffic splitting, or passthrough TLS. Use standard Kubernetes Ingress when portability across Kubernetes distributions is required. OpenShift supports both — the Ingress controller converts Ingress objects to Routes internally.

### Security Context Constraints (SCCs)

SCCs are OpenShift's mechanism for controlling pod security, more mature and granular than Kubernetes's Pod Security Standards. They control which Linux capabilities a pod can request, whether it can run as root, which volumes it can mount, and what host resources it can access.

**Built-in SCCs (ordered from most to least restrictive):**
```
restricted-v2  → Default for all pods. Non-root, no host access, read-only root FS
restricted     → Legacy restricted. Similar but less strict than restricted-v2
nonroot-v2     → Must run as non-root, can set specific UIDs
nonroot        → Legacy nonroot
hostnetwork-v2 → Can use host network and host ports
hostnetwork    → Legacy hostnetwork
hostaccess     → Can access host directories and PID namespace
anyuid         → Can run as any UID including root
privileged     → Full host access — use only for infrastructure components
```

**Granting SCC to a service account:**
```bash
# Grant anyuid SCC to a service account (required for some legacy images)
oc adm policy add-scc-to-user anyuid -z myapp-sa -n myapp

# Check which SCCs a pod can use
oc get pod myapp-pod -o yaml | grep scc

# List all SCCs and their permissions
oc get scc

# Describe a specific SCC
oc describe scc restricted-v2
```

**Custom SCC for application-specific needs:**
```yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: myapp-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegedContainer: false
allowPrivilegeEscalation: false
requiredDropCapabilities:
  - ALL
runAsUser:
  type: MustRunAsRange
  uidRangeMin: 1000
  uidRangeMax: 65534
seLinuxContext:
  type: MustRunAs
fsGroup:
  type: MustRunAs
volumes:
  - configMap
  - downwardAPI
  - emptyDir
  - persistentVolumeClaim
  - projected
  - secret
```

### BuildConfig and ImageStream

BuildConfig and ImageStream are OpenShift-specific resources for building container images and managing image references. While powerful, they are being superseded by external CI/CD tools (Tekton, GitHub Actions, ArgoCD) and OCI registries in modern OpenShift deployments.

**Source-to-Image (S2I) build:**
```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: myapp
  namespace: myapp
spec:
  source:
    type: Git
    git:
      uri: https://github.com/org/myapp.git
      ref: main
  strategy:
    type: Source
    sourceStrategy:
      from:
        kind: ImageStreamTag
        namespace: openshift
        name: java:21
  output:
    to:
      kind: ImageStreamTag
      name: myapp:latest
  triggers:
    - type: GitHub
      github:
        secret: github-webhook-secret
    - type: ImageChange
    - type: ConfigChange
---
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: myapp
  namespace: myapp
spec:
  lookupPolicy:
    local: true
```

**Docker strategy build (using a Dockerfile):**
```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: myapp-docker
  namespace: myapp
spec:
  source:
    type: Git
    git:
      uri: https://github.com/org/myapp.git
      ref: main
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  output:
    to:
      kind: ImageStreamTag
      name: myapp:latest
```

**Modern alternative — use Tekton/ArgoCD instead:**
```yaml
# OpenShift Pipelines (Tekton) replaces BuildConfig for CI
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: myapp-build
  namespace: myapp
spec:
  pipelineRef:
    name: build-and-deploy
  params:
    - name: git-url
      value: https://github.com/org/myapp.git
    - name: image
      value: image-registry.openshift-image-registry.svc:5000/myapp/myapp:latest
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 1Gi
```

### OperatorHub and Operator Lifecycle Manager

OperatorHub is OpenShift's marketplace of pre-packaged operators that automate the installation, upgrade, and lifecycle management of complex applications (databases, monitoring, messaging, storage). OLM (Operator Lifecycle Manager) handles operator installation, dependency resolution, and automatic upgrades.

```bash
# Browse available operators
oc get packagemanifests -n openshift-marketplace

# Install an operator via CLI
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: postgresql
  namespace: openshift-operators
spec:
  channel: stable
  name: postgresql
  source: certified-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Manual    # Require manual approval for upgrades
EOF

# Check operator status
oc get csv -n openshift-operators
oc get installplans -n openshift-operators
```

## Configuration

### Development

Development on OpenShift uses `oc` CLI, the web console, and OpenShift Developer Sandbox or CodeReady Containers (CRC) for local clusters.

```bash
# Login to OpenShift cluster
oc login https://api.cluster.example.com:6443 --token=<token>

# Create a new project (namespace)
oc new-project myapp-dev

# Deploy from Git repository (S2I)
oc new-app https://github.com/org/myapp.git

# Deploy from container image
oc new-app --image=registry.example.com/myapp:latest --name=myapp

# Expose the service via Route
oc expose svc/myapp

# View build logs
oc logs -f bc/myapp

# Port-forward for local debugging
oc port-forward svc/myapp 8080:8080

# Open web console
oc whoami --show-console
```

**Local development with CodeReady Containers:**
```bash
# Install CRC (OpenShift local cluster)
crc setup
crc start --memory 16384 --cpus 6

# Login
eval $(crc oc-env)
oc login -u developer -p developer https://api.crc.testing:6443
```

### Production

Production OpenShift configuration emphasizes RBAC, network policies, resource quotas, and monitoring.

```yaml
# Project template with resource quotas and limits
apiVersion: template.openshift.io/v1
kind: Template
metadata:
  name: project-request
objects:
  - apiVersion: v1
    kind: ResourceQuota
    metadata:
      name: compute-quota
      namespace: ${PROJECT_NAME}
    spec:
      hard:
        requests.cpu: "4"
        requests.memory: 8Gi
        limits.cpu: "8"
        limits.memory: 16Gi
        pods: "20"
  - apiVersion: v1
    kind: LimitRange
    metadata:
      name: default-limits
      namespace: ${PROJECT_NAME}
    spec:
      limits:
        - type: Container
          default:
            cpu: 500m
            memory: 512Mi
          defaultRequest:
            cpu: 100m
            memory: 256Mi
  - apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: deny-all-ingress
      namespace: ${PROJECT_NAME}
    spec:
      podSelector: {}
      policyTypes:
        - Ingress
parameters:
  - name: PROJECT_NAME
    required: true
```

## Performance

**Router performance:** OpenShift's HAProxy-based router handles TLS termination for all Routes. For high-traffic applications, tune the router's thread count and connection limits. Consider deploying application-specific ingress controllers (nginx, Traefik) for workloads that exceed the shared router's capacity.

**ImageStream caching:** ImageStreams cache image metadata locally, reducing registry lookups during pod scheduling. This is a performance advantage in air-gapped or bandwidth-constrained environments. However, ImageStreams add complexity — for new projects, consider using standard image references with `imagePullPolicy: IfNotPresent`.

**Build performance:** S2I builds run on cluster nodes and compete for resources with application workloads. For large projects, dedicate nodes to builds using node selectors, or move builds to an external CI system (Jenkins, GitHub Actions, Tekton) to decouple build and runtime resource consumption.

**Operator overhead:** Each installed operator runs a controller pod that watches for custom resources and reconciles state. In large clusters with many operators, the combined resource consumption of operator controllers can be significant (1-2GB RAM per operator). Install only operators that provide genuine operational value.

## Security

**Default security posture:** OpenShift's default restricted-v2 SCC is significantly more secure than vanilla Kubernetes defaults. It enforces non-root execution, drops all Linux capabilities, prevents host namespace access, and requires read-only root filesystems. This means images that assume root access (many Docker Hub images) will fail on OpenShift without explicit SCC grants.

**Image policy:** OpenShift can enforce image signing and provenance policies:
```bash
# Restrict image sources
oc create -f - <<EOF
apiVersion: config.openshift.io/v1
kind: Image
metadata:
  name: cluster
spec:
  registrySources:
    allowedRegistries:
      - registry.example.com
      - registry.redhat.io
      - quay.io
    blockedRegistries:
      - docker.io
EOF
```

**Network policies:** OpenShift supports Kubernetes NetworkPolicy and OpenShift-specific EgressNetworkPolicy for controlling outbound traffic. Use network policies to isolate namespaces and restrict pod-to-pod communication.

**OAuth integration:** OpenShift includes a built-in OAuth server that integrates with LDAP, Active Directory, GitHub, and OIDC providers for user authentication. Configure identity providers in the OAuth cluster config.

## Testing

**Cluster health:**
```bash
# Cluster operator status
oc get clusteroperators

# Node health
oc get nodes
oc adm top nodes

# Pod health across namespaces
oc get pods -A --field-selector status.phase!=Running,status.phase!=Succeeded

# Check cluster version and update status
oc get clusterversion
```

**Application deployment testing:**
```bash
# Verify deployment rollout
oc rollout status deployment/myapp -n myapp

# Check pod logs
oc logs -f deployment/myapp -n myapp

# Run diagnostic pod
oc debug node/<node-name>

# Test Route accessibility
curl -k https://myapp.apps.cluster.example.com/health

# Verify SCC assignment
oc get pod myapp-xyz -o yaml | grep -A2 "openshift.io/scc"
```

**CI testing with OpenShift:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Login to test cluster
oc login --token="${OPENSHIFT_TOKEN}" --server="${OPENSHIFT_API}"

# Create test namespace
oc new-project test-${CI_PIPELINE_ID} || true

# Deploy application
oc apply -f k8s/test/ -n test-${CI_PIPELINE_ID}
oc rollout status deployment/myapp -n test-${CI_PIPELINE_ID} --timeout=300s

# Run integration tests
ROUTE_URL=$(oc get route myapp -n test-${CI_PIPELINE_ID} -o jsonpath='{.spec.host}')
./gradlew integrationTest -Dbase.url=https://${ROUTE_URL}

# Cleanup
oc delete project test-${CI_PIPELINE_ID}
```

## Dos

- Use standard Kubernetes Deployments instead of OpenShift-specific DeploymentConfigs for new projects.
- Use Routes for TLS termination and traffic management — they are OpenShift's most mature and well-tested ingress mechanism.
- Design container images to run as non-root to work with the default restricted-v2 SCC without requiring elevated permissions.
- Use OperatorHub for installing and managing complex stateful applications (databases, monitoring, messaging).
- Use OpenShift Pipelines (Tekton) or external CI instead of BuildConfig for new CI/CD pipelines.
- Apply resource quotas and limit ranges to all namespaces to prevent resource exhaustion.
- Use network policies to isolate namespaces and control pod-to-pod communication.
- Use `oc adm policy` to audit SCC grants and ensure least-privilege access.

## Don'ts

- Do not use DeploymentConfig for new projects — it is being deprecated in favor of standard Kubernetes Deployments.
- Do not grant `privileged` or `anyuid` SCC without understanding the security implications — most applications can run under `restricted-v2`.
- Do not use OpenShift-specific templates when Helm charts or Kustomize overlays provide better portability.
- Do not ignore the web console — it provides valuable topology views, build logs, and monitoring that CLI commands cannot match.
- Do not install operators without reviewing their resource requirements — each operator adds controller overhead.
- Do not hardcode the OpenShift internal registry URL (`image-registry.openshift-image-registry.svc:5000`) in manifests — use ImageStreams or external registries for portability.
- Do not bypass SCCs with cluster-admin grants to "make things work" — fix the image to run as non-root instead.
- Do not use S2I builds for complex multi-stage Docker builds — S2I is designed for simple source-to-runtime scenarios.
