# React + npm-audit

> Extends `modules/code-quality/npm-audit.md` with React-specific integration.
> Generic npm-audit conventions (flags, CI integration, `.nsprc`) are NOT repeated here.

## Integration Setup

React projects (Vite/CRA) accumulate substantial devDependency trees. Scope production audits to avoid noise from build tooling vulnerabilities:

```json
{
  "scripts": {
    "audit:prod": "npm audit --omit=dev --audit-level=high",
    "audit:all": "npm audit --audit-level=moderate"
  }
}
```

## Framework-Specific Patterns

### Separating runtime vs. build tool advisories

React's build tools (Vite, webpack, Babel, postcss) frequently have moderate advisories that don't affect browser-delivered bundles. Use `--omit=dev` in CI to gate only on production dependency vulnerabilities:

```yaml
# .github/workflows/security.yml
- name: Audit production deps
  run: npm audit --omit=dev --audit-level=high
```

### Common React ecosystem advisories

Known patterns that generate false-positive risk assessments:

- `nth-check` (via `svgo` → `react-scripts`) — only exploitable server-side with untrusted CSS input; irrelevant in build tools.
- `postcss` line-return vulnerability — only affects PostCSS parsing of external stylesheets, not build-time usage.

Document accepted advisories in `.nsprc` or `.auditignore` with justification:

```json
{
  "exceptions": [
    { "id": 1086957, "reason": "nth-check in svgo/react-scripts — build-tool only, no runtime exposure" }
  ]
}
```

### Vite projects vs. CRA

Vite has a significantly smaller dependency tree than Create React App. Vite projects typically produce 0 production advisories; CRA projects may accumulate stale transitive advisories from `react-scripts`. Prefer Vite for new projects.

## Additional Dos

- Run `npm audit --omit=dev` in CI production gates, `npm audit` (all deps) in scheduled weekly scans.
- Document accepted moderate advisories in a `SECURITY.md` or inline `.auditignore` — avoid silent `npm audit fix --force` in automated pipelines.

## Additional Don'ts

- Don't run `npm audit fix --force` in CI — it can silently upgrade major versions and break builds.
- Don't use `npm audit` results as the only security gate — supplement with Dependabot or Snyk for automatic PR-level alerts.
