# Express + npm-audit

> Extends `modules/code-quality/npm-audit.md` with Express-specific integration.
> Generic npm-audit conventions (audit levels, fix strategies, CI integration) are NOT repeated here.

## Integration Setup

No additional packages required — npm-audit is built into npm:

```json
{
  "scripts": {
    "audit:prod": "npm audit --omit=dev --audit-level=high",
    "audit:full": "npm audit --audit-level=moderate",
    "audit:ci": "npm audit --omit=dev --audit-level=high --json > audit-report.json"
  }
}
```

## Framework-Specific Patterns

### Express Core Packages to Watch

Express ecosystem packages are frequently targeted by supply chain attacks and prototype pollution CVEs. Prioritize auditing these:

| Package | Common CVE Patterns | Action |
|---|---|---|
| `express` | Prototype pollution, path traversal | Upgrade minor/patch promptly |
| `body-parser` | ReDoS, prototype pollution | Bundled since Express 4.16 — ensure not using old standalone version |
| `cookie-parser` | Secret exposure in logs | Upgrade; audit middleware order |
| `morgan` | Log injection | Upgrade; sanitize user data before logging |
| `multer` | Path traversal in file uploads | Upgrade; validate `filename` callback |
| `jsonwebtoken` | Algorithm confusion, weak secret | Upgrade; set `algorithms` explicitly |

### Prototype Pollution Risk

Express middleware and route handlers are exposed to user-controlled JSON bodies. Vulnerabilities in JSON parsers can lead to prototype pollution:

```bash
# Check for known prototype pollution advisories
npm audit --json | jq '.vulnerabilities | to_entries[] | select(.value.via[] | strings | contains("prototype"))'
```

Use `--audit-level=moderate` for Express APIs — moderate advisories in request-handling packages can be exploitable via crafted HTTP requests.

### Production-Only Audit in CI

```yaml
- name: Security audit (production deps only)
  run: npm audit --omit=dev --audit-level=high
  # Use --audit-level=moderate for public-facing APIs
```

## Additional Dos

- Use `--omit=dev --audit-level=high` as a CI gate for Express projects — development tool vulnerabilities rarely affect production runtime.
- Audit `body-parser`, `express`, and authentication middleware packages immediately when advisories appear — they process untrusted input directly.
- Review `npm audit fix --force` output manually before applying — Express major version bumps can remove or rename middleware APIs.

## Additional Don'ts

- Don't use `--audit-level=critical` only for Express APIs that handle authentication or file uploads — `high` severity vulnerabilities in these packages are often exploitable.
- Don't ignore advisory descriptions for packages in the request-handling path — a low-traffic vector in middleware can become a full RCE depending on input shape.
- Don't commit `package-lock.json` with `--ignore-scripts` applied globally — some Express dependencies (native modules) require lifecycle scripts to build.
