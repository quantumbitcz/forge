# Tekton

## Overview

Kubernetes-native CI/CD framework using CRDs (Tasks, Pipelines, Runs as pods). Pipelines run as K8s workloads, leveraging cluster scheduling, RBAC, and observability.

- **Use for:** K8s-native orgs, supply chain security (SLSA via Tekton Chains), custom task images, workspace sharing via PVCs
- **Avoid for:** teams without K8s expertise, small projects (use GitHub Actions/GitLab CI), orgs that can't maintain K8s infrastructure
- **Key features:** Tekton Chains (SLSA provenance + artifact signing), Tekton Triggers (event-driven), TektonHub (reusable tasks), GitOps-compatible pipeline definitions, workspace data sharing via PVCs/ConfigMaps/Secrets

## Architecture Patterns

### Tasks and Pipelines

Tekton's core primitives are Tasks (units of work) and Pipelines (orchestrations of Tasks). A Task contains a sequence of Steps, each running in a container within the same pod. A Pipeline references multiple Tasks, defining their dependency graph, workspace bindings, and parameter passing. TaskRuns and PipelineRuns are the execution instances of Tasks and Pipelines.

**Task definition (`tasks/gradle-build.yaml`):**
```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: gradle-build
  labels:
    app.kubernetes.io/version: "1.0"
spec:
  params:
    - name: gradle-tasks
      type: string
      default: "build"
    - name: java-version
      type: string
      default: "21"
    - name: gradle-args
      type: string
      default: "--no-daemon --parallel --warning-mode=all"
  workspaces:
    - name: source
      description: The workspace containing the source code
    - name: gradle-cache
      description: Gradle dependency cache
      optional: true
  results:
    - name: build-version
      description: The version of the built artifact
    - name: test-passed
      description: Whether tests passed
  steps:
    - name: build
      image: gradle:8.12-jdk$(params.java-version)
      workingDir: $(workspaces.source.path)
      env:
        - name: GRADLE_USER_HOME
          value: $(workspaces.gradle-cache.path)
      script: |
        #!/usr/bin/env bash
        set -euo pipefail

        ./gradlew $(params.gradle-tasks) $(params.gradle-args)

        # Extract build version
        VERSION=$(./gradlew properties -q | grep '^version:' | awk '{print $2}')
        echo -n "$VERSION" > $(results.build-version.path)
        echo -n "true" > $(results.test-passed.path)

    - name: collect-test-results
      image: alpine:3.20
      workingDir: $(workspaces.source.path)
      script: |
        #!/usr/bin/env sh
        echo "Test results:"
        find . -name "TEST-*.xml" -path "*/test-results/*" | head -20
```

**Pipeline definition (`pipelines/ci-pipeline.yaml`):**
```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: ci-pipeline
spec:
  params:
    - name: repo-url
      type: string
    - name: revision
      type: string
      default: main
    - name: image-registry
      type: string
    - name: image-name
      type: string

  workspaces:
    - name: shared-workspace
    - name: gradle-cache
    - name: docker-credentials

  tasks:
    - name: fetch-source
      taskRef:
        name: git-clone
      workspaces:
        - name: output
          workspace: shared-workspace
      params:
        - name: url
          value: $(params.repo-url)
        - name: revision
          value: $(params.revision)

    - name: build-and-test
      taskRef:
        name: gradle-build
      runAfter:
        - fetch-source
      workspaces:
        - name: source
          workspace: shared-workspace
        - name: gradle-cache
          workspace: gradle-cache
      params:
        - name: gradle-tasks
          value: "build"

    - name: security-scan
      taskRef:
        name: trivy-scanner
      runAfter:
        - fetch-source
      workspaces:
        - name: manifest-dir
          workspace: shared-workspace
      params:
        - name: ARGS
          value:
            - "fs"
            - "--severity"
            - "HIGH,CRITICAL"
            - "."

    - name: build-image
      taskRef:
        name: kaniko
      runAfter:
        - build-and-test
        - security-scan
      workspaces:
        - name: source
          workspace: shared-workspace
        - name: dockerconfig
          workspace: docker-credentials
      params:
        - name: IMAGE
          value: "$(params.image-registry)/$(params.image-name):$(tasks.fetch-source.results.commit)"

    - name: deploy-staging
      taskRef:
        name: kubernetes-deploy
      runAfter:
        - build-image
      params:
        - name: namespace
          value: staging
        - name: image
          value: "$(params.image-registry)/$(params.image-name):$(tasks.fetch-source.results.commit)"

  finally:
    - name: notify
      taskRef:
        name: slack-notify
      params:
        - name: message
          value: "Pipeline $(context.pipelineRun.name) completed with status $(tasks.status)"
```

Key concepts: `runAfter:` creates task dependencies — `build-image` runs only after both `build-and-test` and `security-scan` complete. Workspaces share data between tasks via PVCs. Results pass small values (< 4KB) between tasks via the results mechanism. The `finally:` block runs regardless of pipeline success/failure — useful for notifications and cleanup.

### Triggers (EventListener, TriggerTemplate, TriggerBinding)

Tekton Triggers enable event-driven pipeline execution. An EventListener receives webhooks (GitHub, GitLab, Bitbucket, or custom sources), a TriggerBinding extracts parameters from the event payload, and a TriggerTemplate creates a PipelineRun with those parameters. This decouples pipeline definitions from event sources.

**EventListener with GitHub webhook:**
```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: github-listener
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
    - name: github-push
      interceptors:
        - ref:
            name: github
          params:
            - name: secretRef
              value:
                secretName: github-webhook-secret
                secretKey: token
            - name: eventTypes
              value:
                - push
                - pull_request
        - ref:
            name: cel
          params:
            - name: filter
              value: >-
                body.ref.startsWith('refs/heads/main') ||
                header.canonical('X-GitHub-Event')[0] == 'pull_request'
      bindings:
        - ref: github-push-binding
      template:
        ref: ci-pipeline-template

---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-push-binding
spec:
  params:
    - name: repo-url
      value: $(body.repository.clone_url)
    - name: revision
      value: $(body.head_commit.id)
    - name: repo-name
      value: $(body.repository.name)

---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: ci-pipeline-template
spec:
  params:
    - name: repo-url
    - name: revision
    - name: repo-name
  resourcetemplates:
    - apiVersion: tekton.dev/v1
      kind: PipelineRun
      metadata:
        generateName: ci-$(tt.params.repo-name)-
        labels:
          tekton.dev/pipeline: ci-pipeline
          app.kubernetes.io/managed-by: tekton-triggers
      spec:
        pipelineRef:
          name: ci-pipeline
        params:
          - name: repo-url
            value: $(tt.params.repo-url)
          - name: revision
            value: $(tt.params.revision)
          - name: image-registry
            value: registry.example.com
          - name: image-name
            value: $(tt.params.repo-name)
        workspaces:
          - name: shared-workspace
            volumeClaimTemplate:
              spec:
                accessModes:
                  - ReadWriteOnce
                resources:
                  requests:
                    storage: 1Gi
          - name: gradle-cache
            persistentVolumeClaim:
              claimName: gradle-cache-pvc
          - name: docker-credentials
            secret:
              secretName: docker-registry-credentials
```

The interceptors validate the webhook signature (preventing spoofed events) and filter events using CEL expressions (Common Expression Language). The TriggerBinding extracts repository URL, commit SHA, and repository name from the GitHub webhook payload. The TriggerTemplate creates a PipelineRun with a VolumeClaimTemplate for ephemeral storage and persistent PVCs for caches.

### TektonHub (Catalog Tasks)

TektonHub provides a catalog of community-contributed Tasks that cover common CI/CD operations: `git-clone`, `kaniko` (rootless Docker builds), `buildah`, `trivy-scanner`, `grype`, `kustomize`, `helm-upgrade-from-source`, and more. Catalog tasks are versioned and installed via `kubectl apply` or the `tkn` CLI.

**Installing catalog tasks:**
```bash
# Install git-clone task from Tekton Hub
tkn hub install task git-clone --version 0.9

# Install kaniko for container image builds
tkn hub install task kaniko --version 0.6

# Install trivy for vulnerability scanning
tkn hub install task trivy-scanner --version 0.2

# List installed tasks
tkn task list
```

**Using catalog tasks in pipelines:**
```yaml
tasks:
  - name: fetch-source
    taskRef:
      name: git-clone
    params:
      - name: url
        value: $(params.repo-url)
      - name: revision
        value: $(params.revision)
      - name: deleteExisting
        value: "true"
    workspaces:
      - name: output
        workspace: shared-workspace

  - name: build-image
    taskRef:
      name: kaniko
    runAfter:
      - build-and-test
    params:
      - name: IMAGE
        value: $(params.image-registry)/$(params.image-name):$(params.revision)
      - name: EXTRA_ARGS
        value:
          - "--cache=true"
          - "--cache-repo=$(params.image-registry)/$(params.image-name)/cache"
    workspaces:
      - name: source
        workspace: shared-workspace
      - name: dockerconfig
        workspace: docker-credentials
```

Kaniko builds container images without requiring Docker daemon access or privileged containers — it runs in user space, making it the recommended image builder for Tekton on multi-tenant clusters.

### Tekton Chains (Supply Chain Security)

Tekton Chains automatically observes TaskRuns and PipelineRuns, generates SLSA provenance attestations, and signs artifacts. It provides the strongest supply chain security story in CI/CD — every build produces a signed attestation documenting exactly what was built, from which source, using which tools, and producing which artifacts. This provenance is verifiable by downstream consumers and compliant with SLSA Level 3 requirements.

**Configuring Tekton Chains:**
```bash
# Install Tekton Chains
kubectl apply -f https://storage.googleapis.com/tekton-releases/chains/latest/release.yaml

# Configure signing with cosign
kubectl patch configmap chains-config \
  -n tekton-chains \
  --type merge \
  -p '{"data": {
    "artifacts.taskrun.format": "in-toto",
    "artifacts.taskrun.storage": "oci",
    "artifacts.taskrun.signer": "x509",
    "artifacts.oci.storage": "oci",
    "artifacts.oci.format": "simplesigning",
    "transparency.enabled": "true"
  }}'

# Generate and store signing key
cosign generate-key-pair k8s://tekton-chains/signing-secrets
```

**Task annotated for Chains provenance:**
```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: build-and-push
spec:
  params:
    - name: IMAGE
      type: string
  workspaces:
    - name: source
  results:
    - name: IMAGE_DIGEST
      description: Digest of the built image
    - name: IMAGE_URL
      description: URL of the built image
  steps:
    - name: build-push
      image: gcr.io/kaniko-project/executor:latest
      args:
        - --destination=$(params.IMAGE)
        - --context=$(workspaces.source.path)
        - --digest-file=$(results.IMAGE_DIGEST.path)
      script: |
        echo -n "$(params.IMAGE)" > $(results.IMAGE_URL.path)
```

When this task completes, Tekton Chains automatically:
1. Captures the task inputs (source commit, parameters) and outputs (image digest).
2. Generates an in-toto attestation documenting the build provenance.
3. Signs the attestation with the configured key.
4. Stores the signed attestation alongside the OCI image in the registry.
5. Optionally uploads the attestation to a transparency log (Rekor) for public verifiability.

**Verifying provenance:**
```bash
# Verify image signature
cosign verify --key cosign.pub registry.example.com/my-app@sha256:abc123

# Verify SLSA provenance
cosign verify-attestation \
  --key cosign.pub \
  --type slsaprovenance \
  registry.example.com/my-app@sha256:abc123
```

## Configuration

### Development

**Development cluster setup:**
```bash
# Install Tekton Pipelines
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Install Tekton Triggers
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml

# Install Tekton Dashboard
kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml

# Install tkn CLI
brew install tektoncd-cli

# Verify installation
tkn version
kubectl get pods -n tekton-pipelines
```

**Running a pipeline locally for development:**
```bash
# Start a PipelineRun
tkn pipeline start ci-pipeline \
  --param repo-url=https://github.com/my-org/my-app.git \
  --param revision=main \
  --param image-registry=registry.example.com \
  --param image-name=my-app \
  --workspace name=shared-workspace,volumeClaimTemplateFile=pvc-template.yaml \
  --workspace name=gradle-cache,claimName=gradle-cache-pvc \
  --workspace name=docker-credentials,secret=docker-registry-credentials \
  --showlog

# Follow pipeline logs
tkn pipelinerun logs ci-pipeline-run-abc -f

# List pipeline runs
tkn pipelinerun list
```

**Workspace PVC template (`pvc-template.yaml`):**
```yaml
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: standard
```

### Production

**Production Tekton configuration with resource limits and cleanup:**
```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: production-pipeline
  annotations:
    tekton.dev/pipelines.minVersion: "0.50.0"
spec:
  params:
    - name: repo-url
      type: string
    - name: revision
      type: string
    - name: target-environment
      type: string
      default: staging

  workspaces:
    - name: shared-workspace
    - name: gradle-cache
    - name: docker-credentials
    - name: kubeconfig

  tasks:
    - name: fetch-source
      taskRef:
        name: git-clone
      workspaces:
        - name: output
          workspace: shared-workspace
      params:
        - name: url
          value: $(params.repo-url)
        - name: revision
          value: $(params.revision)

    - name: build-test
      taskRef:
        name: gradle-build
      runAfter: [fetch-source]
      workspaces:
        - name: source
          workspace: shared-workspace
        - name: gradle-cache
          workspace: gradle-cache
      timeout: 15m

    - name: vulnerability-scan
      taskRef:
        name: trivy-scanner
      runAfter: [fetch-source]
      workspaces:
        - name: manifest-dir
          workspace: shared-workspace
      timeout: 10m

    - name: build-push-image
      taskRef:
        name: build-and-push
      runAfter: [build-test, vulnerability-scan]
      workspaces:
        - name: source
          workspace: shared-workspace
        - name: dockerconfig
          workspace: docker-credentials
      params:
        - name: IMAGE
          value: "registry.example.com/my-app:$(tasks.fetch-source.results.commit)"
      timeout: 10m

    - name: deploy
      taskRef:
        name: kubernetes-deploy
      runAfter: [build-push-image]
      workspaces:
        - name: kubeconfig
          workspace: kubeconfig
      params:
        - name: namespace
          value: $(params.target-environment)
        - name: image
          value: "registry.example.com/my-app:$(tasks.fetch-source.results.commit)"
      timeout: 5m

  finally:
    - name: cleanup
      taskRef:
        name: cleanup-workspace
      workspaces:
        - name: workspace
          workspace: shared-workspace

    - name: notify-result
      taskRef:
        name: slack-notify
      params:
        - name: message
          value: |
            Pipeline: $(context.pipelineRun.name)
            Status: $(tasks.status)
            Commit: $(params.revision)
```

**PipelineRun resource limits:**
```yaml
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: production-run
spec:
  pipelineRef:
    name: production-pipeline
  taskRunTemplate:
    podTemplate:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        fsGroup: 1001
      nodeSelector:
        workload: ci
      tolerations:
        - key: ci-workload
          operator: Exists
          effect: NoSchedule
  params:
    - name: repo-url
      value: https://github.com/my-org/my-app.git
    - name: revision
      value: abc123def
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 5Gi
    - name: gradle-cache
      persistentVolumeClaim:
        claimName: gradle-cache-pvc
    - name: docker-credentials
      secret:
        secretName: docker-registry-credentials
    - name: kubeconfig
      secret:
        secretName: kubeconfig-production
```

The `taskRunTemplate.podTemplate` applies to all task pods: non-root execution, node affinity for CI workload nodes, and filesystem group ownership for shared workspace volumes.

## Performance

**Workspace strategies** significantly impact pipeline performance. Ephemeral workspaces (VolumeClaimTemplate) are created per PipelineRun and deleted afterward — clean but slow for first use. Persistent workspaces (PVC) retain data between runs — faster for cached dependencies but require cleanup management:

```yaml
# Ephemeral — clean, slow first run
workspaces:
  - name: shared-workspace
    volumeClaimTemplate:
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 2Gi

# Persistent — fast, requires cleanup
workspaces:
  - name: gradle-cache
    persistentVolumeClaim:
      claimName: gradle-cache-pvc
```

Use ephemeral workspaces for source code (clean checkout every run) and persistent workspaces for caches (Gradle, npm, Maven dependencies).

**Task-level timeouts** prevent stuck tasks from blocking the pipeline:
```yaml
tasks:
  - name: build
    taskRef:
      name: gradle-build
    timeout: 15m
```

**Pipeline-level concurrency** — use Kubernetes resource quotas to limit concurrent PipelineRuns:
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tekton-limits
  namespace: tekton-builds
spec:
  hard:
    pods: "20"
    requests.cpu: "40"
    requests.memory: "80Gi"
```

**Kaniko caching** for faster image builds:
```yaml
params:
  - name: EXTRA_ARGS
    value:
      - "--cache=true"
      - "--cache-repo=registry.example.com/my-app/cache"
      - "--cache-ttl=168h"
```

**Step resource requests** prevent pod scheduling delays:
```yaml
steps:
  - name: build
    image: gradle:8.12-jdk21
    resources:
      requests:
        cpu: "1"
        memory: "4Gi"
      limits:
        cpu: "4"
        memory: "8Gi"
```

## Security

**Pod security contexts** enforce non-root execution and read-only root filesystems:
```yaml
apiVersion: tekton.dev/v1
kind: PipelineRun
spec:
  taskRunTemplate:
    podTemplate:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        fsGroup: 65532
        seccompProfile:
          type: RuntimeDefault
```

**RBAC for Tekton resources** — restrict who can create PipelineRuns and access secrets:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tekton-developer
  namespace: tekton-builds
rules:
  - apiGroups: ["tekton.dev"]
    resources: ["pipelineruns", "taskruns"]
    verbs: ["create", "get", "list", "watch"]
  - apiGroups: ["tekton.dev"]
    resources: ["pipelines", "tasks"]
    verbs: ["get", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tekton-admin
  namespace: tekton-builds
rules:
  - apiGroups: ["tekton.dev"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["create", "get", "update", "delete"]
```

**Tekton Chains for SLSA provenance** — automatically sign and attest every build. Combined with admission controllers (Kyverno, OPA Gatekeeper), enforce that only signed images with valid provenance can be deployed:
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-signed-images
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-image-signature
      match:
        any:
          - resources:
              kinds: ["Pod"]
      verifyImages:
        - imageReferences: ["registry.example.com/*"]
          attestors:
            - entries:
                - keys:
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      ...
                      -----END PUBLIC KEY-----
```

**Secret management** — use Kubernetes Secrets for credentials, mounted as workspace volumes. For production, integrate with external secret managers:
```yaml
workspaces:
  - name: docker-credentials
    secret:
      secretName: docker-registry-credentials
```

**Security checklist:**
- Enable Tekton Chains for automatic SLSA provenance and artifact signing.
- Run all task steps as non-root with read-only root filesystems where possible.
- Use Kubernetes RBAC to restrict PipelineRun creation and secret access.
- Use Kaniko or Buildah for rootless image builds — never mount the Docker socket.
- Validate webhook signatures in EventListener interceptors.
- Use network policies to restrict task pod network access.
- Store signing keys in external KMS (AWS KMS, GCP KMS, HashiCorp Vault) rather than Kubernetes Secrets.
- Enforce signed image policies with admission controllers.

## Testing

**Running tasks locally with `tkn`:**
```bash
# Run a single task
tkn task start gradle-build \
  --param gradle-tasks=test \
  --workspace name=source,claimName=test-source-pvc \
  --showlog

# Run a pipeline with all parameters
tkn pipeline start ci-pipeline \
  --param repo-url=https://github.com/my-org/my-app.git \
  --param revision=main \
  --param image-registry=registry.example.com \
  --param image-name=my-app \
  --workspace name=shared-workspace,volumeClaimTemplateFile=pvc-template.yaml \
  --showlog

# Describe a task run (view params, results, conditions)
tkn taskrun describe gradle-build-run-abc

# View pipeline run status
tkn pipelinerun describe ci-pipeline-run-abc
```

**Testing tasks in isolation:**
```bash
# Create a test TaskRun
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: test-gradle-build
spec:
  taskRef:
    name: gradle-build
  params:
    - name: gradle-tasks
      value: "test"
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: test-source-pvc
    - name: gradle-cache
      emptyDir: {}
EOF

# Watch task run
tkn taskrun logs test-gradle-build -f
```

**Validating Tekton resources:**
```bash
# Validate YAML against Tekton CRD schema
kubectl apply --dry-run=server -f tasks/gradle-build.yaml
kubectl apply --dry-run=server -f pipelines/ci-pipeline.yaml

# Validate triggers
kubectl apply --dry-run=server -f triggers/
```

**Testing EventListeners:**
```bash
# Port-forward the EventListener service
kubectl port-forward svc/el-github-listener 8080

# Send a test webhook
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -H "X-Hub-Signature-256: sha256=$(echo -n '{}' | openssl dgst -sha256 -hmac $WEBHOOK_SECRET | awk '{print $2}')" \
  -d '{
    "ref": "refs/heads/main",
    "head_commit": {"id": "abc123"},
    "repository": {"clone_url": "https://github.com/my-org/my-app.git", "name": "my-app"}
  }'

# Verify PipelineRun was created
tkn pipelinerun list
```

## Dos

- Use Tekton Chains for automatic SLSA provenance generation and artifact signing. This provides verifiable supply chain security for every build without additional pipeline steps.
- Use Kaniko (or Buildah) for container image builds. They run in user space without Docker daemon access or privileged containers, which is essential for multi-tenant Kubernetes clusters.
- Use workspace-backed PVCs for dependency caches (Gradle, npm, Maven) and VolumeClaimTemplates for ephemeral source code storage. Persistent caches dramatically reduce build times.
- Use Tekton Triggers with webhook signature validation for event-driven pipeline execution. CEL interceptors filter events before creating PipelineRuns, preventing unnecessary builds.
- Use task-level `timeout:` to prevent stuck tasks from blocking pipelines. Set timeouts proportional to expected task duration with reasonable headroom.
- Use `finally:` tasks for cleanup and notification. They run regardless of pipeline success or failure, ensuring workspaces are cleaned and teams are notified.
- Run all task steps as non-root. Configure `securityContext.runAsNonRoot: true` in the PipelineRun's `podTemplate`. Root execution in CI is unnecessary and risky.
- Use TektonHub catalog tasks for common operations (git-clone, image building, scanning). They are community-maintained and follow best practices.
- Use Kubernetes RBAC to restrict who can create PipelineRuns and access secrets in the Tekton namespace.

## Don'ts

- Don't mount the Docker socket (`/var/run/docker.sock`) into task steps. Socket mounting grants root-equivalent access to the host, compromising cluster security. Use Kaniko or Buildah for rootless builds.
- Don't store secrets in Task or Pipeline YAML. Use Kubernetes Secrets mounted as workspaces. For production, integrate with external secret managers (Vault, AWS Secrets Manager, GCP Secret Manager).
- Don't use `emptyDir` workspaces for data that needs to persist between pipeline runs (dependency caches). EmptyDir volumes are destroyed when the pod terminates. Use PVCs for persistent data.
- Don't skip webhook signature validation in EventListeners. Without validation, anyone who knows the EventListener URL can trigger pipeline runs, consuming cluster resources and potentially deploying malicious code.
- Don't create PipelineRuns without resource limits. Unbounded task pods can consume all cluster resources, starving other workloads. Set CPU and memory requests and limits on task steps.
- Don't use `latest` tags for task step images. Pin to specific versions or digests for reproducibility. A `latest` tag can change between runs, producing different results from the same pipeline definition.
- Don't ignore PipelineRun cleanup. Completed PipelineRuns and their associated pods, PVCs, and logs accumulate. Configure the Tekton Pipelines controller's pruner or use a CronJob to clean up old runs.
- Don't skip the `finally:` block. Without cleanup tasks, ephemeral workspaces may not be released, and teams may not be notified of pipeline failures.
- Don't run Tekton on under-provisioned clusters. Pipeline pods compete for resources with application workloads. Use dedicated node pools or resource quotas to isolate CI workloads.
