# Vue + npm-audit

> Extends `modules/code-quality/npm-audit.md` with Vue-specific integration.
> Generic npm-audit conventions (flags, CI integration, advisory management) are NOT repeated here.

## Integration Setup

```json
{
  "scripts": {
    "audit:prod": "npm audit --omit=dev --audit-level=high",
    "audit:all": "npm audit --audit-level=moderate"
  }
}
```

## Framework-Specific Patterns

### Vite devDependency advisory noise

Vite-based Vue projects (created via `npm create vue@latest`) have minimal production dependency trees. Most advisories affect devDependencies only. Gate CI on `--omit=dev`:

```yaml
- name: Audit production deps
  run: npm audit --omit=dev --audit-level=high
```

### Nuxt vs. standalone Vue

**Nuxt projects:** Production dependencies include Nitro, H3, and server-side packages — audit both prod and dev separately since Nuxt runs server-side code:

```bash
# Nuxt — server code is production, audit thoroughly
npm audit --audit-level=moderate
```

**Standalone Vue (Vite):** Only `vue`, `vue-router`, `pinia` (and optionally `axios` / `@tanstack/vue-query`) are production dependencies — extremely small audit surface.

### Vue ecosystem advisory patterns

Common benign advisories in Vue projects:

- `vite` devDependency vulnerabilities — build-tool only, no browser exposure.
- `rollup` transitive advisories — internal to Vite's build pipeline.
- `esbuild` SSRF advisory — only exploitable when esbuild's dev server is exposed; not applicable in production builds.

Document accepted advisories with justification in a `.nsprc` or project `SECURITY.md`.

## Additional Dos

- Audit `package-lock.json` in CI — `npm ci` ensures reproducible installs before auditing.
- For Nuxt projects, include `--audit-level=moderate` since server-side packages (H3, ofetch) are production runtime code.

## Additional Don'ts

- Don't skip auditing Nuxt's production dependencies — Nuxt server routes run in production and carry real exploit surface.
- Don't ignore `vue`, `vue-router`, or `pinia` advisories regardless of severity — these are runtime production packages.
