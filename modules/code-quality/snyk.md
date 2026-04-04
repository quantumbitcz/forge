---
name: snyk
categories: [security-scanner]
languages: [javascript, typescript, java, kotlin, python, ruby, go, php, scala, csharp, swift, dart]
exclusive_group: none
recommendation_score: 80
detection_files: [.snyk, snyk.yml]
---

# snyk

## Overview

Snyk is a commercial multi-language security platform covering dependency vulnerabilities (`snyk test`), container image scanning (`snyk container test`), infrastructure-as-code misconfiguration detection (`snyk iac test`), and SAST (`snyk code test`). It queries the Snyk Vulnerability Database — a proprietary, curated superset of the NVD with faster CVE publication and fix guidance. Requires authentication via `SNYK_TOKEN`. Use `.snyk` policy file for ignore management. Output SARIF for GitHub Advanced Security integration. The free tier covers open-source scanning; container, IaC, and SAST require a paid plan.

## Architecture Patterns

### Installation & Setup

```bash
# Install Snyk CLI
npm install -g snyk

# Or via Homebrew
brew install snyk

# Authenticate (interactive — opens browser)
snyk auth

# Authenticate via token (CI/non-interactive)
export SNYK_TOKEN="your-snyk-token"

# Test dependencies for vulnerabilities (exits non-zero if found)
snyk test

# Test with severity threshold (fail only on high/critical)
snyk test --severity-threshold=high

# Monitor project (sends snapshot to Snyk platform for ongoing monitoring)
snyk monitor

# Container scanning
snyk container test myimage:latest

# IaC scanning
snyk iac test ./infrastructure/

# SAST (Snyk Code — requires paid plan)
snyk code test
```

**Package manager integration:**
```bash
# Node.js (reads package-lock.json)
snyk test

# Python (reads requirements.txt or Pipfile.lock)
snyk test --file=requirements.txt

# Go (reads go.sum)
snyk test

# Java/Kotlin (reads pom.xml or build.gradle)
snyk test --file=build.gradle

# Ruby (reads Gemfile.lock)
snyk test --file=Gemfile.lock
```

### Rule Categories

| Finding Type | Description | Pipeline Severity |
|---|---|---|
| Critical (CVSS >= 9.0) | Exploitable, weaponized CVE | CRITICAL |
| High (CVSS 7.0–8.9) | Significant exploitable vulnerability | CRITICAL |
| Medium (CVSS 4.0–6.9) | Exploitable with conditions | WARNING |
| Low (CVSS < 4.0) | Limited or theoretical impact | INFO |
| License issue | Non-OSS-compatible license | WARNING |

### Configuration Patterns

**`.snyk` policy file (project root):**
```yaml
# Snyk (https://snyk.io) policy file
version: v1.25.0
ignore:
  SNYK-JS-LODASH-1040724:
    - "*":
        reason: "Prototype pollution — project does not use affected merge() code path"
        expires: "2025-12-31T00:00:00.000Z"
        created: "2024-01-15T00:00:00.000Z"
patch: {}
```

**`snyk.config.json` for project-level defaults:**
```json
{
  "severity-threshold": "high",
  "fail-on": "all",
  "org": "my-org-name",
  "project-name": "my-service"
}
```

**Excluding paths from scanning:**
```bash
# Exclude test directories from snyk test
snyk test --exclude=test,__tests__,spec

# Exclude from snyk iac test
snyk iac test --exclude=.terraform
```

### CI Integration

```yaml
# .github/workflows/security.yml
- name: Install Snyk
  run: npm install -g snyk

- name: Snyk test (dependencies)
  env:
    SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
  run: snyk test --severity-threshold=high --sarif-file-output=snyk-dep.sarif || true

- name: Snyk container test
  env:
    SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
  run: |
    snyk container test ${{ env.IMAGE_NAME }}:${{ github.sha }} \
      --severity-threshold=high \
      --sarif-file-output=snyk-container.sarif || true

- name: Snyk Code (SAST)
  env:
    SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
  run: snyk code test --sarif-file-output=snyk-code.sarif || true

- name: Upload Snyk results to GitHub Security
  if: always()
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: snyk-dep.sarif
    category: snyk-dependencies

- name: Snyk monitor (track in Snyk platform)
  if: github.ref == 'refs/heads/main'
  env:
    SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
  run: snyk monitor --org=my-org --project-name=my-service

# Use official Snyk GitHub Action
- name: Snyk Action
  uses: snyk/actions/node@master
  env:
    SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
  with:
    args: --severity-threshold=high
```

## Performance

- `snyk test` makes API calls to the Snyk platform — network latency varies by plan (1-15 seconds for dependency scans). Use `--json` for faster output parsing.
- `snyk container test` downloads and analyzes the image manifest — large images (> 500MB) can take 2-5 minutes. Pull the image before running snyk to leverage Docker layer cache.
- `snyk monitor` sends a dependency snapshot to the Snyk platform for continuous monitoring — run it only on main branch merges, not on every PR, to avoid plan usage limits.
- `snyk code test` (SAST) performs local analysis with a remote engine — expect 30-120 seconds for large codebases.
- Use `--org` to specify your Snyk organization explicitly — default org lookup adds a round-trip API call.

## Security

- Store `SNYK_TOKEN` as a CI secret — never commit it or include it in Docker build args. Rotate tokens via the Snyk web UI.
- Every entry in the `.snyk` policy `ignore` section requires `reason` and `expires` fields — Snyk enforces these fields in some configurations but teams should always include them for audit compliance.
- `snyk monitor` creates a persistent project in the Snyk dashboard — ensure the project name (`--project-name`) is consistent across branches to avoid duplicate project entries.
- Snyk's "Fix PR" feature auto-generates upgrade PRs on the Snyk platform — review these PRs carefully; automated upgrades can introduce breaking changes.
- For IaC scanning, `snyk iac test` covers Terraform, Kubernetes manifests, CloudFormation, and Helm charts — run it in the same pipeline as `snyk test` for holistic coverage.

## Testing

```bash
# Test all dependencies
snyk test

# Test with SARIF output
snyk test --sarif

# Test a specific file
snyk test --file=package.json

# Container image scan
snyk container test nginx:latest

# IaC scan
snyk iac test ./k8s/

# SAST scan
snyk code test

# Monitor (sends to dashboard)
snyk monitor

# Check .snyk policy is valid
snyk policy

# Show Snyk version and auth status
snyk --version
snyk auth --check
```

## Dos

- Store `SNYK_TOKEN` as a CI secret and never hardcode it — the token grants access to your organization's Snyk dashboard and vulnerability reports.
- Use `.snyk` policy file for all ignores — command-line `--ignore` flags bypass version control and are not auditable.
- Run `snyk monitor` on main branch merges only — it records the current dependency state for continuous monitoring without consuming API credits on every PR.
- Use `--sarif-file-output` and upload to GitHub Advanced Security for unified security findings across all Snyk scan types (deps, container, code, IaC).
- Set `--severity-threshold=high` in CI to block on high/critical only — low/medium findings should be tracked but not block deployments.

## Don'ts

- Don't set `SNYK_TOKEN` as a plain environment variable in Dockerfiles or `docker-compose.yml` — it will be embedded in image layers or committed to source control.
- Don't add `.snyk` policy ignores without an `expires` date — permanent ignores for known vulnerabilities are a compliance and audit risk.
- Don't rely on Snyk alone for all security scanning in a JVM project — pair with OWASP Dependency-Check which uses the NVD database directly for offline/air-gapped compatibility.
- Don't run `snyk monitor` on every PR — it creates duplicate project snapshots in the Snyk dashboard and may exhaust plan-level API credits.
- Don't disable Snyk Fix PR integration without a replacement process — automated dependency upgrade PRs are the most reliable path to staying patched.
- Don't skip `snyk container test` for services with custom Docker images — OS-level package vulnerabilities are not caught by `snyk test`.
