# Kubernetes Documentation Conventions

> Support tier: community

> Extends `modules/documentation/conventions.md` with Kubernetes-specific patterns.
> Note: k8s uses `language: null` — there is no code doc section.

## Manifest Documentation

- Every `Deployment`, `StatefulSet`, and `CronJob` manifest must have a `metadata.annotations` block with at minimum: `description`, `owner`, and `managed-by`.
- Document non-obvious resource requests/limits with an annotation explaining the rationale.
- ConfigMap and Secret keys: include an inline comment (YAML `#`) above each key explaining its purpose and format.
- Helm charts: every value in `values.yaml` must have a preceding `#` comment documenting the field, its type, and its effect.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  annotations:
    description: "REST API server — stateless, horizontally scalable"
    owner: "platform-team"
    managed-by: "helm"
spec:
  template:
    spec:
      containers:
        - name: api
          resources:
            requests:
              # Baseline for 50 req/s; increase if p99 latency exceeds 200ms
              cpu: "250m"
              memory: "256Mi"
```

## Architecture Documentation

- Maintain a cluster architecture doc showing namespaces, their purpose, and inter-namespace communication policies.
- Document RBAC policies: list `ServiceAccount` → `ClusterRole`/`Role` → `RoleBinding` relationships and the principle-of-least-privilege rationale.
- Network policies: document ingress/egress rules per namespace — what is allowed and what is denied by default.
- Document Helm chart values overrides per environment (dev, staging, prod) — maintain a `values-{env}.yaml` reference in the architecture doc.
- Ingress configuration: document hostname routing rules, TLS termination, and cert-manager integration.

## Diagram Guidance

- **Cluster topology:** C4 Context or Mermaid flowchart showing namespaces and their services.
- **Network policies:** Mermaid flowchart showing allowed inter-namespace traffic flows.
- **GitOps pipeline:** Sequence diagram showing ArgoCD/FluxCD reconciliation flow.

## Dos

- Annotate all workload manifests with `description` and `owner`
- Document resource limits with rationale annotations — future operators need the context
- Keep `values.yaml` comments as the authoritative reference for Helm chart configuration

## Don'ts

- Don't document Kubernetes API fields that are self-explanatory — focus on project-specific choices
- Don't store secret values in documentation — reference the secret management system (Vault, SOPS, etc.)
- Don't pin to `latest` image tags in manifests — document the tagging strategy instead
