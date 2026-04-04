---
name: npm-audit
categories: [security-scanner]
languages: [javascript, typescript]
exclusive_group: none
recommendation_score: 90
detection_files: [package-lock.json, package.json]
---

# npm-audit

## Overview

`npm audit` is npm's built-in dependency vulnerability scanner, querying the npm Advisory Database (backed by GitHub Advisory Database). It runs automatically during `npm install` and explicitly via `npm audit`. No installation required — ships with npm 6+. Use `--audit-level=high` to fail only on high/critical advisories while allowing low/moderate findings through. Run `npm audit fix` to auto-upgrade non-breaking patches; review `npm audit fix --force` manually before applying as it may introduce breaking major-version changes. Separate production from development scanning with `--omit=dev`.

## Architecture Patterns

### Installation & Setup

Built into npm — no additional packages required:

```bash
# Ensure npm is up to date for the latest advisory database support
npm install -g npm@latest

# Basic audit (all severities)
npm audit

# Fail CI on high/critical only
npm audit --audit-level=high

# Production dependencies only (excludes devDependencies)
npm audit --omit=dev --audit-level=high

# Machine-readable output
npm audit --json

# Auto-fix within semver range
npm audit fix

# Auto-fix allowing major-version bumps (review output before applying)
npm audit fix --force --dry-run
```

**package.json script integration:**
```json
{
  "scripts": {
    "audit:prod": "npm audit --omit=dev --audit-level=high",
    "audit:full": "npm audit --audit-level=moderate",
    "audit:json": "npm audit --json > audit-report.json"
  }
}
```

### Rule Categories

| Severity | CVSS Range | Default Behavior | Pipeline Severity |
|---|---|---|---|
| critical | 9.0–10.0 | Fails `--audit-level=critical` | CRITICAL |
| high | 7.0–8.9 | Fails `--audit-level=high` | CRITICAL |
| moderate | 4.0–6.9 | Fails `--audit-level=moderate` | WARNING |
| low | 0.1–3.9 | Informational only | INFO |
| info | — | Informational only | INFO |

### Configuration Patterns

**`.npmrc` for project-level defaults:**
```ini
# .npmrc
audit-level=high
fund=false
```

**Ignoring specific advisories via `npm audit --json` + filtering:**
```bash
# Parse JSON and exclude a specific advisory ID
npm audit --json | jq '
  .vulnerabilities | to_entries[] |
  select(.value.via | map(select(type == "object" and .url != null and (.url | contains("GHSA-xxxx-yyyy-zzzz")) | not)) | length > 0)
'
```

**Using `overrides` in package.json to patch transitive vulnerabilities:**
```json
{
  "overrides": {
    "vulnerable-transitive-dep": "^2.1.0"
  }
}
```
Use `overrides` (npm 8.3+) when a vulnerable transitive dependency cannot be updated via the direct dependency. Document each override with a comment in `package.json` or a separate `SECURITY-OVERRIDES.md`.

**pnpm / yarn equivalents:**
```bash
pnpm audit --audit-level high     # pnpm built-in
yarn npm audit --all              # Yarn Berry built-in
```

### CI Integration

```yaml
# .github/workflows/security.yml
- name: npm audit (production deps)
  run: npm audit --omit=dev --audit-level=high

- name: Upload audit report as artifact
  if: failure()
  run: npm audit --json > audit-report.json
  continue-on-error: true

- name: Upload audit report
  if: failure()
  uses: actions/upload-artifact@v4
  with:
    name: npm-audit-report
    path: audit-report.json

- name: npm audit SARIF (via audit-ci)
  run: |
    npx audit-ci --high --report-type full --output-format sarif > audit.sarif
  continue-on-error: true
- uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: audit.sarif
    category: npm-audit
```

For richer output and `.auditcirc.json` configuration, use `audit-ci` (npm package):
```bash
npm install --save-dev audit-ci
```
```json
// .auditcirc.json
{
  "high": true,
  "allowlist": ["GHSA-xxxx-yyyy-zzzz"],
  "report-type": "full"
}
```

## Performance

- `npm audit` makes a network request to the npm registry advisory endpoint — it adds 2-5 seconds to CI. Cache `~/.npm` between CI runs to speed up registry lookups.
- Use `--omit=dev` in production pipeline steps — it reduces the advisory surface and speeds up the check by excluding development tooling CVEs that don't affect production deployments.
- `npm audit --json` output is suitable for machine parsing; avoid `--parseable` format (legacy, less structured).
- In monorepos with workspaces, run `npm audit` from the root — it scans the hoisted `node_modules` as well as workspace-specific dependencies.

## Security

- `npm audit` only scans packages in `node_modules` — it will not find vulnerabilities in packages listed in `package.json` but not yet installed. Always run `npm install` before `npm audit` in CI.
- `npm audit fix --force` can introduce breaking changes (major version bumps) — always review the diff with `--dry-run` first and run the full test suite after applying.
- Transitive dependency vulnerabilities where the direct parent has no fix available require manual `overrides` with a documented rationale and a tracking issue for removal when the parent is patched.
- Review `npm audit fix` output for peer dependency warnings — forced upgrades can silently install incompatible versions.
- Do not dismiss advisories because the vulnerable code path seems unreachable — attackers frequently find indirect exploit paths through complex dependency graphs.

## Testing

```bash
# Full audit with all severities shown
npm audit

# Fail on high/critical only (suitable for CI gate)
npm audit --audit-level=high

# Production-only scan
npm audit --omit=dev

# Preview fix without modifying package-lock.json
npm audit fix --dry-run

# Apply safe fixes (within semver range)
npm audit fix

# Check a single package
npm audit --json | jq '.vulnerabilities["lodash"]'

# Count vulnerabilities by severity
npm audit --json | jq '.metadata.vulnerabilities'
```

## Dos

- Run `npm audit --omit=dev --audit-level=high` in CI on every PR — catching vulnerabilities before merge is cheaper than patching after release.
- Use `overrides` in `package.json` to patch transitive vulnerabilities when the direct dependency owner is slow to release a fix.
- Document every advisory in the `allowlist` (via `audit-ci`) with a JIRA/Linear issue link and a planned resolution date.
- Pin critical dependencies to exact versions in `package.json` to prevent silent upgrades to vulnerable versions during `npm install`.
- Separate production (`--omit=dev`) and full scans — development-only CVEs should not block production deployments but should still be tracked.

## Don'ts

- Don't run `npm audit fix --force` without reviewing the output with `--dry-run` first — it can introduce breaking major-version changes that break tests.
- Don't rely on `npm audit` alone for container-level security — it only covers npm packages, not OS-level packages in the Docker image.
- Don't permanently ignore advisories in `allowlist` without an expiry condition — include a comment with the expected fix date and check quarterly.
- Don't run `npm audit` without running `npm install` first in CI — scanning an empty or stale `node_modules` produces false negatives.
- Don't set `--audit-level=critical` in CI as the sole gate — high-severity vulnerabilities are routinely exploited and should also block merges.
- Don't suppress all moderate findings globally — evaluate each one; some moderate-severity advisories have critical impact in specific usage patterns (e.g., ReDoS in hot paths).
