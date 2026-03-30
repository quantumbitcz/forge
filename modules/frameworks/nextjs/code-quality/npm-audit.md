# Next.js + npm-audit

> Extends `modules/code-quality/npm-audit.md` with Next.js-specific integration.
> Generic npm-audit conventions (flags, CI integration, advisory management) are NOT repeated here.

## Integration Setup

```json
{
  "scripts": {
    "audit:prod": "npm audit --omit=dev --audit-level=high",
    "audit:server": "npm audit --audit-level=moderate"
  }
}
```

## Framework-Specific Patterns

### Next.js as a production server

Next.js runs in production as a Node.js server (or serverless functions). Unlike a pure SPA, `next`, `react`, `react-dom`, and any server-side packages are production runtime dependencies — audit them at `moderate` level:

```bash
# Gate CI on: next, react, react-dom, and direct production deps
npm audit --audit-level=moderate
```

### Server Action security surface

Next.js Server Actions are server-side code reachable from the browser — any advisory in packages used within Server Actions carries real exploit potential. Audit production deps strictly.

### Advisory patterns in Next.js projects

Common Next.js ecosystem advisories:

| Package | Advisory type | Risk |
|---|---|---|
| `next` | Usually low/moderate | MUST remediate — production server |
| `sharp` (image optimization) | Occasional | Remediate — used at request time |
| `@vercel/og` (OG image gen) | Rare | Remediate — server-side |
| `webpack` | Often dev-only | `--omit=dev` excludes |

### Verifying production vs. dev deps

```bash
# List production dependencies only
npm ls --omit=dev --depth=0

# Audit only production dep tree
npm audit --omit=dev --json | jq '.metadata.vulnerabilities'
```

### Keeping Next.js updated

Next.js publishes patch releases frequently for security fixes. Set up Dependabot:

```yaml
# .github/dependabot.yml
- package-ecosystem: "npm"
  directory: "/"
  schedule: { interval: "weekly" }
  groups:
    nextjs: { patterns: ["next", "eslint-config-next", "@next/*"] }
```

## Additional Dos

- Treat Next.js as a server-side runtime — audit at `--audit-level=moderate` for production CI gates.
- Enable Dependabot for automated `next` patch updates — Next.js issues security patches frequently.

## Additional Don'ts

- Don't use `--omit=dev` as the only gate for Next.js — server-side packages are production runtime, so moderate advisories matter.
- Don't apply `npm audit fix --force` to `next` — major version upgrades of Next.js require migration work; use the official upgrade guide.
