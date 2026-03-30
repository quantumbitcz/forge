# Kubernetes + Trivy

> Extends `modules/code-quality/trivy.md` with Kubernetes-specific integration.
> Generic Trivy conventions (installation, `.trivy.yaml`, SARIF output, SBOM generation, CI integration) are NOT repeated here.

## Integration Setup

Trivy covers K8s workloads at three levels: container image vulnerabilities (`trivy image`), YAML manifest misconfigurations (`trivy config`), and live cluster audit (`trivy k8s`). Run all three in CI:

```bash
# Scan container images referenced in manifests
trivy image --severity HIGH,CRITICAL --exit-code 1 myimage:latest

# Scan K8s manifests for misconfigurations
trivy config --severity HIGH,CRITICAL --exit-code 1 ./k8s/

# Live cluster audit (requires kubeconfig)
trivy k8s --report summary --severity HIGH,CRITICAL cluster
```

## Framework-Specific Patterns

### `trivy config` for K8s YAML misconfiguration

`trivy config` applies Trivy's built-in Kubernetes policies (derived from NSA/CISA K8s Hardening Guide and CIS Benchmark) to manifests, Helm charts, and Kustomize bases:

```bash
# Scan all K8s YAML files
trivy config ./k8s/ --severity HIGH,CRITICAL --exit-code 1

# Scan a Helm chart (renders values first)
trivy config ./helm/mychart/ --helm-values ./helm/mychart/values-prod.yaml

# Scan Kustomize output (pipe rendered manifests)
kubectl kustomize ./k8s/overlays/production | trivy config -

# Detailed output showing failing policies
trivy config ./k8s/ --format table
```

Key K8s misconfiguration checks enforced by `trivy config`:

| Check | Severity | What It Catches |
|---|---|---|
| `KSV001` | HIGH | Container running as root |
| `KSV003` | HIGH | No `defaultDenyEgress` NetworkPolicy |
| `KSV011` | MEDIUM | CPU limits not set |
| `KSV012` | HIGH | `allowPrivilegeEscalation: true` |
| `KSV014` | HIGH | Writable root filesystem |
| `KSV017` | CRITICAL | Privileged container |
| `KSV020` | HIGH | Container runs as UID 0 |
| `KSV030` | HIGH | No seccomp profile |

### `trivy-operator` for continuous cluster scanning

`trivy-operator` runs Trivy as a Kubernetes operator — it scans workloads continuously and exposes findings as `VulnerabilityReport` and `ConfigAuditReport` CRDs rather than requiring per-CI-run invocations:

```bash
# Install trivy-operator via Helm
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo update
helm install trivy-operator aqua/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  --set="trivy.ignoreUnfixed=true"

# Query vulnerability reports
kubectl get vulnerabilityreports --all-namespaces
kubectl get configauditreports --all-namespaces

# Get JSON output for a specific workload
kubectl get vulnerabilityreport -n my-namespace deployment-my-app -o json
```

### Namespace-scoped reports

Scope `trivy k8s` to specific namespaces for targeted CI gates per service:

```bash
# Scan only the production namespace
trivy k8s --report all --namespace production --severity HIGH,CRITICAL

# Scan a specific workload
trivy k8s --report all deployment/my-api --namespace production

# Output as JSON for processing
trivy k8s --report all --namespace production --format json --output k8s-report.json
```

### CI integration — image build + manifest scan pipeline

```yaml
# .github/workflows/security.yml
- name: Build container image
  run: docker build -t ${{ env.IMAGE_NAME }}:${{ github.sha }} .

- name: Trivy image scan
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.IMAGE_NAME }}:${{ github.sha }}
    severity: HIGH,CRITICAL
    exit-code: 1
    format: sarif
    output: trivy-image.sarif

- name: Trivy K8s manifest scan
  run: |
    trivy config ./k8s/ \
      --severity HIGH,CRITICAL \
      --exit-code 1 \
      --format sarif \
      --output trivy-config.sarif

- name: Upload SARIF to GitHub Security
  if: always()
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: trivy-image.sarif
    category: trivy-image

- name: Upload manifest scan SARIF
  if: always()
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: trivy-config.sarif
    category: trivy-k8s-config

- name: Generate SBOM for container image
  run: |
    trivy image \
      --format cyclonedx \
      --output sbom.cdx.json \
      ${{ env.IMAGE_NAME }}:${{ github.sha }}

- name: Upload SBOM
  uses: actions/upload-artifact@v4
  with:
    name: sbom-${{ github.sha }}
    path: sbom.cdx.json
```

## Additional Dos

- Run `trivy config` against Helm chart rendered output (with production `values.yaml`) — default values often enable insecure settings that production values override; scan the rendered result, not the templates.
- Install `trivy-operator` in staging and production clusters for continuous detection between deployments — CI scans are point-in-time; the operator catches newly published CVEs without a redeploy.
- Scope `trivy k8s` to specific namespaces per team — all-namespace cluster scans in CI produce overwhelming output; use namespace-scoped runs to enforce per-service accountability.

## Additional Don'ts

- Don't skip `trivy config ./k8s/` when images pass `trivy image` — misconfigured RBAC, missing NetworkPolicies, and privileged containers are YAML-level issues invisible to image scanning.
- Don't add K8s-specific CVE IDs to `.trivyignore` without namespace and workload context — a CVE acceptable in a batch job namespace may be unacceptable in the ingress or auth namespace.
- Don't rely on `trivy k8s` live cluster scan as the primary CI gate — live cluster state drifts from manifests; use `trivy config` on manifests for deterministic CI checks, and `trivy k8s` for continuous monitoring.
