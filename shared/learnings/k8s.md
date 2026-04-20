---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
# Cross-Project Learnings: k8s

## PREEMPT items

### K8-PREEMPT-001: Missing resource limits causes noisy-neighbor OOM kills
- **Domain:** resource-management
- **Pattern:** Pods without memory limits can consume all node memory and trigger OOM kills of other pods. Always set memory requests AND limits. CPU limits are optional with HPA but memory limits are mandatory. Use `LimitRange` at namespace level as a safety net.
- **Confidence:** HIGH
- **Hit count:** 0

### K8-PREEMPT-002: Liveness probe on startup kills slow-starting containers
- **Domain:** health
- **Pattern:** Liveness probes that start checking immediately kill containers that take longer to start (JVM warmup, migration, cache preload). Use a `startupProbe` with `failureThreshold * periodSeconds > max startup time` to protect the startup phase before liveness takes over.
- **Confidence:** HIGH
- **Hit count:** 0

### K8-PREEMPT-003: Readiness and liveness probes on the same endpoint hides deadlocks
- **Domain:** health
- **Pattern:** Using the same endpoint for both readiness and liveness probes masks different failure modes. Readiness (`/readyz`) should check dependencies (DB, cache); liveness (`/healthz`) should only verify the process is not deadlocked. Separate the endpoints.
- **Confidence:** HIGH
- **Hit count:** 0

### K8-PREEMPT-004: Image tag :latest defeats reproducibility and rollback
- **Domain:** deployment
- **Pattern:** Using `:latest` tag means the same manifest can deploy different code. Rollbacks with `kubectl rollout undo` do nothing because the tag has not changed. Pin images to immutable tags (`:{semver}`, `:{git-sha}`) or digests (`@sha256:...`).
- **Confidence:** HIGH
- **Hit count:** 0

### K8-PREEMPT-005: Missing PodDisruptionBudget causes downtime during node drain
- **Domain:** availability
- **Pattern:** Without a `PodDisruptionBudget`, cluster upgrades and node drains can evict all replicas simultaneously. Set `minAvailable` or `maxUnavailable` on all critical workloads to ensure at least one pod remains running during voluntary disruptions.
- **Confidence:** HIGH
- **Hit count:** 0

### K8-PREEMPT-006: Secrets stored in ConfigMaps are visible in plain text
- **Domain:** security
- **Pattern:** ConfigMaps are not encrypted and are visible to anyone with read access to the namespace. Database passwords, API keys, and tokens must use Kubernetes Secrets (or External Secrets Operator / Sealed Secrets). Mark secrets as `immutable: true` to prevent accidental changes.
- **Confidence:** HIGH
- **Hit count:** 0

### K8-PREEMPT-007: CPU limits set too low cause constant throttling
- **Domain:** performance
- **Pattern:** CPU limits trigger CFS throttling even when the node has spare capacity. Pods appear slow but show no errors. Set CPU requests to expected usage but consider omitting CPU limits when HPA is configured, or set limits generously (2-3x request) to avoid throttling.
- **Confidence:** HIGH
- **Hit count:** 0

### K8-PREEMPT-008: Default ServiceAccount has excessive permissions in some clusters
- **Domain:** security
- **Pattern:** The `default` ServiceAccount in a namespace may have auto-mounted tokens and broad permissions depending on cluster config. Always create a dedicated ServiceAccount per workload with only the required RBAC permissions. Set `automountServiceAccountToken: false` when no API access is needed.
- **Confidence:** MEDIUM
- **Hit count:** 0

### K8-PREEMPT-009: Missing NetworkPolicy allows unrestricted pod-to-pod traffic
- **Domain:** security
- **Pattern:** Without NetworkPolicy, every pod can communicate with every other pod in the cluster. Apply a default-deny ingress policy per namespace, then whitelist specific pod-to-pod communication via label selectors.
- **Confidence:** HIGH
- **Hit count:** 0
