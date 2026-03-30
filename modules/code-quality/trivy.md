# trivy

## Overview

Trivy is an open-source multi-target vulnerability scanner by Aqua Security covering filesystem dependencies (`trivy fs .`), container images (`trivy image`), IaC misconfigurations (`trivy config`), Kubernetes clusters (`trivy k8s`), and SBOM generation (CycloneDX and SPDX formats). It queries multiple databases including the Trivy DB (NVD + GitHub Advisory + distro-specific advisories). Configure via `.trivy.yaml`. Use `--severity HIGH,CRITICAL` to fail builds on exploitable findings and `--exit-code 1` for CI gates. Trivy requires no authentication for open-source use — it is the recommended free-tier alternative to Snyk for container and filesystem scanning.

## Architecture Patterns

### Installation & Setup

```bash
# Install Trivy (Linux)
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# macOS
brew install trivy

# Docker (no install)
docker run --rm -v $(pwd):/workspace aquasec/trivy:latest fs /workspace

# Filesystem scan (dependencies + secrets + IaC)
trivy fs .

# Container image scan
trivy image myimage:latest

# IaC misconfiguration scan
trivy config ./infrastructure/

# Kubernetes cluster scan
trivy k8s --report summary cluster

# SBOM generation (CycloneDX)
trivy fs . --format cyclonedx --output sbom.cdx.json

# SBOM generation (SPDX)
trivy image myimage:latest --format spdx-json --output sbom.spdx.json

# CI gate: fail on HIGH/CRITICAL only
trivy fs . --severity HIGH,CRITICAL --exit-code 1
```

### Rule Categories

| Category | Scanner | Pipeline Severity |
|---|---|---|
| CRITICAL vulnerability | CVE with CVSS >= 9.0 in dep or OS pkg | CRITICAL |
| HIGH vulnerability | CVE with CVSS 7.0–8.9 | CRITICAL |
| MEDIUM vulnerability | CVE with CVSS 4.0–6.9 | WARNING |
| LOW vulnerability | CVE with CVSS < 4.0 | INFO |
| IaC misconfiguration (HIGH) | Security policy violation in Terraform/K8s/Helm | CRITICAL |
| Secret detection | Hardcoded API keys, passwords, tokens | CRITICAL |
| License violation | Non-OSS-compatible license | WARNING |

### Configuration Patterns

**`.trivy.yaml` (project root):**
```yaml
# .trivy.yaml
scan:
  security-checks:
    - vuln
    - secret
    - config
  severity:
    - HIGH
    - CRITICAL

db:
  skip-db-update: false   # set to true in air-gapped environments

cache:
  dir: ~/.cache/trivy

report:
  format: sarif
  output: trivy-report.sarif

# Vulnerability ignore list
vulnerability:
  ignore-statuses:
    - will_not_fix    # ignore distro packages with no fix available
    - end_of_life
  ignore-unfixed: false  # report all CVEs, including unfixed

# File pattern ignores
.trivyignore: .trivyignore  # reference to ignore file
```

**`.trivyignore` (ignore specific CVEs):**
```
# .trivyignore
# CVE-2023-12345 - False positive: only affects Alpine 3.16, we use Alpine 3.19
CVE-2023-12345

# GHSA-xxxx-yyyy-zzzz - Upstream fix released in next minor, tracking #1234
GHSA-xxxx-yyyy-zzzz
```

**Multi-scanner pipeline:**
```bash
# Full scan: deps + secrets + IaC misconfigurations
trivy fs . \
  --security-checks vuln,secret,config \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --format sarif \
  --output trivy-fs.sarif

# Container scan with OS + app layer vulnerability detection
trivy image \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --format sarif \
  --output trivy-image.sarif \
  myimage:latest
```

### CI Integration

```yaml
# .github/workflows/security.yml
- name: Install Trivy
  run: |
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

- name: Cache Trivy vulnerability database
  uses: actions/cache@v4
  with:
    path: ~/.cache/trivy
    key: trivy-db-${{ github.run_id }}
    restore-keys: trivy-db-

- name: Trivy filesystem scan (deps + secrets)
  run: |
    trivy fs . \
      --security-checks vuln,secret \
      --severity HIGH,CRITICAL \
      --exit-code 1 \
      --format sarif \
      --output trivy-fs.sarif

- name: Trivy IaC config scan
  if: always()
  run: |
    trivy config ./infrastructure/ \
      --severity HIGH,CRITICAL \
      --exit-code 1 \
      --format sarif \
      --output trivy-iac.sarif || true

- name: Trivy container image scan
  run: |
    trivy image \
      --severity HIGH,CRITICAL \
      --exit-code 1 \
      --format sarif \
      --output trivy-image.sarif \
      ${{ env.IMAGE_NAME }}:${{ github.sha }}

- name: Generate CycloneDX SBOM
  run: |
    trivy image \
      --format cyclonedx \
      --output sbom.cdx.json \
      ${{ env.IMAGE_NAME }}:${{ github.sha }}

- name: Upload SARIF to GitHub Security
  if: always()
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: trivy-fs.sarif
    category: trivy-filesystem

- name: Upload SBOM as release artifact
  uses: actions/upload-artifact@v4
  with:
    name: sbom-cyclonedx
    path: sbom.cdx.json

# Use official Trivy GitHub Action
- name: Trivy Action
  uses: aquasecurity/trivy-action@master
  with:
    scan-type: fs
    scan-ref: .
    severity: HIGH,CRITICAL
    exit-code: 1
    format: sarif
    output: trivy-results.sarif
```

## Performance

- Trivy downloads its vulnerability database (~100MB) on first run — cache `~/.cache/trivy` in CI to avoid re-downloading on every run. The cache key should NOT include a run ID for maximum reuse; use a daily timestamp instead.
- `trivy image` pulls the Docker image before scanning — use `docker pull` before the Trivy step to leverage Docker layer cache.
- Use `--skip-db-update` in performance-critical pipelines if the cache is fresh enough — combine with a nightly database refresh job.
- Filesystem scans on large Node.js projects can be slow due to scanning thousands of small files in `node_modules` — use `--skip-dirs node_modules` if the package manager lockfile scan is sufficient.
- `--parallel` flag (default: 5) controls the number of concurrent goroutines — increase for faster scanning on multi-core CI agents.

## Security

- Trivy's secret scanning (`--security-checks secret`) detects hardcoded credentials using regex patterns — enable it alongside vulnerability scanning as it catches a different class of issue.
- `.trivyignore` entries must include a comment explaining the justification — undocumented ignores are equivalent to undocumented suppressions in any other scanner.
- Run `trivy image` against the final built image, not the base image — application-layer dependencies (OS packages installed via `RUN apt-get`) may introduce vulnerabilities absent in the base.
- For production container images, use distroless or Alpine base images — they have a significantly smaller attack surface than Debian/Ubuntu full images.
- Combine `trivy config` with `kube-bench` for Kubernetes security auditing — Trivy covers declarative misconfigurations, kube-bench covers runtime cluster hardening.

## Testing

```bash
# Filesystem scan
trivy fs .

# Container image scan
trivy image nginx:latest

# IaC misconfiguration scan
trivy config ./infrastructure/

# Generate CycloneDX SBOM
trivy fs . --format cyclonedx --output sbom.cdx.json

# Generate SPDX SBOM
trivy fs . --format spdx-json --output sbom.spdx.json

# Scan with HIGH/CRITICAL only (CI gate)
trivy fs . --severity HIGH,CRITICAL --exit-code 1

# Secret detection only
trivy fs . --security-checks secret

# Show all findings including fixed
trivy image --ignore-unfixed=false myimage:latest

# Update vulnerability database manually
trivy db --reset
```

## Dos

- Cache `~/.cache/trivy` in CI with a daily cache key — avoids the 100MB database download on every run while still getting daily CVE updates.
- Use `--severity HIGH,CRITICAL --exit-code 1` as the CI gate — fail builds on exploitable findings and track lower severities as informational.
- Generate a CycloneDX SBOM with `--format cyclonedx` and attach it to every release artifact — required for supply chain compliance (SLSA, FedRAMP).
- Use `.trivyignore` (version-controlled) rather than `--ignore-policy` command-line flags — all accepted false positives must have a justification comment.
- Run both `trivy fs .` (application dependencies) and `trivy image` (container OS packages + app layer) — they cover different vulnerability surfaces.

## Don'ts

- Don't use `--skip-db-update` in release pipelines — stale databases miss recent CVEs published since the last cache refresh.
- Don't add CVEs to `.trivyignore` without comments explaining the justification — trivy ignore entries without context become permanent blind spots.
- Don't rely on `trivy fs .` alone for container-based services — OS-level package vulnerabilities are only visible via `trivy image`.
- Don't use `--ignore-unfixed` in release pipeline gates — marking unfixed CVEs as acceptable without review understates actual risk.
- Don't scan the source directory with `trivy fs .` and skip `trivy config` for Kubernetes/Terraform projects — IaC misconfigurations are a distinct and significant attack surface.
- Don't pin Trivy to an old version in CI — Trivy's scanner improvements and new vulnerability signatures require staying current (within the last 3 months).
