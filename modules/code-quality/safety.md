---
name: safety
categories: [security-scanner]
languages: [python]
exclusive_group: none
recommendation_score: 80
detection_files: [.safety-policy.yml, requirements.txt, pyproject.toml]
---

# safety

## Overview

Safety CLI scans Python project dependencies for known security vulnerabilities using the PyUp.io Safety DB (a curated superset of the NVD for Python packages). Supports both `safety check` (legacy, reads from `requirements.txt` or installed packages) and the modern `safety scan` (project-aware, reads `pyproject.toml`, `setup.py`, or `requirements*.txt`). The free tier uses a time-delayed community database; the commercial Safety Platform (PyUp.io) provides real-time CVE data, policy management, and CI integrations. Configure scan behavior and ignores in `.safety-policy.yml` to keep the ignore list auditable and version-controlled.

## Architecture Patterns

### Installation & Setup

```bash
# Install Safety CLI
pip install safety

# Or as a development dependency in pyproject.toml
# [project.optional-dependencies]
# dev = ["safety>=3.0"]

# Modern project scan (reads pyproject.toml / requirements files)
safety scan

# Legacy check (reads installed packages or requirements file)
safety check
safety check -r requirements.txt

# Exit code 1 on any vulnerability (suitable for CI)
safety scan --exit-code

# JSON output for machine parsing
safety scan --output json > safety-report.json

# SARIF output for GitHub Security tab upload
safety scan --output sarif > safety.sarif
```

**Authenticate for real-time database (Safety Platform):**
```bash
safety auth login
# Or via API key
export SAFETY_API_KEY="your-api-key"
safety scan
```

### Rule Categories

| Severity | Criteria | Pipeline Severity |
|---|---|---|
| critical | CVSS >= 9.0 | CRITICAL |
| high | CVSS 7.0–8.9 | CRITICAL |
| medium | CVSS 4.0–6.9 | WARNING |
| low | CVSS < 4.0 | INFO |
| unknown | No CVSS score available | WARNING |

### Configuration Patterns

**`.safety-policy.yml` (project root):**
```yaml
version: "3.0"

security:
  ignore-cvss-severity-below: 0     # report all severities
  ignore-unpinned-requirements: false
  continue-on-vulnerability-error: false

ignore-vulnerabilities:
  # Ignore a specific vulnerability with mandatory reason and expiry
  - id: "70612"
    reason: "Vulnerability only affects Python < 3.6; project requires 3.11+"
    expires: "2025-12-31"

report:
  # Include remediation notes
  remediations: true
```

**`pyproject.toml` integration:**
```toml
[tool.safety]
policy_file = ".safety-policy.yml"
```

**pip-audit as alternative/complement:**
```bash
pip install pip-audit
pip-audit --requirement requirements.txt --format sarif --output pip-audit.sarif
```
`pip-audit` (maintained by PyPA) queries the OSV database and is useful as a second opinion alongside Safety.

### CI Integration

```yaml
# .github/workflows/security.yml
- name: Install Safety
  run: pip install safety

- name: Safety scan
  env:
    SAFETY_API_KEY: ${{ secrets.SAFETY_API_KEY }}
  run: safety scan --output sarif > safety.sarif || true

- name: Check for vulnerabilities (fail on high/critical)
  env:
    SAFETY_API_KEY: ${{ secrets.SAFETY_API_KEY }}
  run: safety scan --exit-code

- name: Upload Safety SARIF
  if: always()
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: safety.sarif
    category: safety

# For Docker-based projects, also scan the installed packages inside the image
- name: Safety scan (Docker image packages)
  run: |
    docker run --rm python:3.11-slim pip freeze | \
      docker run --rm -i python:3.11-slim sh -c "pip install safety && safety check --stdin"
```

**Pre-commit hook:**
```yaml
# .pre-commit-config.yaml
- repo: https://github.com/Lucas-C/pre-commit-hooks-safety
  rev: v1.3.3
  hooks:
    - id: python-safety-dependencies-check
      args: ["--short-report"]
```

## Performance

- `safety scan` is fast (< 5 seconds) — it reads the local requirements files and queries a cached database snapshot. Network latency is negligible unless fetching a fresh database.
- The free Safety DB is updated daily; the paid Safety Platform provides real-time updates. For high-security environments, use the paid tier with `SAFETY_API_KEY`.
- Pin the `safety` version in `requirements-dev.txt` to avoid behavior changes between scans — Safety 3.x introduced breaking output format changes from 2.x.
- In large monorepos with multiple `requirements*.txt` files, scan each environment separately: `safety scan -r requirements.txt`, `safety scan -r requirements-dev.txt`.

## Security

- Store `SAFETY_API_KEY` as a CI secret — never commit it to source code or include it in Docker images.
- Every entry in `.safety-policy.yml` `ignore-vulnerabilities` must include a `reason` and `expires` field — unexplained or permanent ignores hide real risk.
- Run `safety scan` against both `requirements.txt` and `requirements-dev.txt` — development tool vulnerabilities (e.g., in pytest plugins) can be exploited in CI/CD pipelines.
- When using virtual environments, activate the environment before running `safety check` to ensure the correct package versions are scanned.
- Combine Safety with `bandit` (SAST) for full Python security coverage — Safety covers dependency CVEs; bandit covers insecure code patterns.

## Testing

```bash
# Basic project scan
safety scan

# Legacy requirements file scan
safety check -r requirements.txt

# Check specific package version
safety check -r requirements.txt --package "requests==2.25.0"

# Generate full report with remediations
safety scan --detailed-output

# JSON output for CI artifact
safety scan --output json > safety-report.json

# Verify .safety-policy.yml is valid
safety validate

# Scan with policy file
safety scan --policy-file .safety-policy.yml
```

## Dos

- Use `.safety-policy.yml` for all ignores — never use `--ignore` CLI flags in CI scripts, which bypass version control and audit trails.
- Pin `safety` to a specific version in `requirements-dev.txt` — Safety 3.x and 2.x have incompatible CLI interfaces and output formats.
- Authenticate with `SAFETY_API_KEY` in CI to access the real-time database — the unauthenticated community database has a 24-hour delay on new advisories.
- Run `safety scan` on all requirements files (`requirements.txt`, `requirements-dev.txt`, `requirements-test.txt`) separately to catch vulnerabilities across all environments.
- Combine with `pip-audit` for defense-in-depth — Safety uses PyUp.io DB, pip-audit uses OSV DB; they have complementary coverage.

## Don'ts

- Don't use `--ignore` flags in CI command lines — all ignores must go in `.safety-policy.yml` with justification and expiry.
- Don't run `safety check` without specifying a requirements file or activating the virtual environment — scanning globally installed packages produces misleading results.
- Don't skip `.safety-policy.yml` expiry dates on ignored vulnerabilities — without expiry, ignored CVEs accumulate silently and are never reassessed.
- Don't rely on Safety as the only security measure — it only covers known CVEs in PyPI packages. Use `bandit` for source code scanning and container scanning for OS-level vulnerabilities.
- Don't use the unauthenticated free tier for production pipelines — the 24-hour database delay means new critical CVEs appear in production before CI catches them.
- Don't ignore `unknown` severity vulnerabilities without investigation — Safety marks vulnerabilities as unknown when CVSS scores are not yet available, not when they are low risk.
