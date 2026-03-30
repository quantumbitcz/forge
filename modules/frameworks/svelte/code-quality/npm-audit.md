# Svelte + npm-audit

> Extends `modules/code-quality/npm-audit.md` with Svelte-specific integration.
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

### Svelte standalone vs. SvelteKit

**Standalone Svelte (Vite SPA):** Production dependencies are minimal — typically only `svelte` itself. `svelte` has an excellent security track record. Most advisories affect devDependencies only:

```bash
# Standalone Svelte — audit only what ships to the browser
npm audit --omit=dev --audit-level=high
```

**SvelteKit (see `modules/frameworks/sveltekit/code-quality/npm-audit.md`):** SvelteKit includes server-side packages — different audit scope.

### Vite advisory patterns

Vite-based builds frequently have `esbuild` SSRF advisories. These are dev-server only vulnerabilities (Vite's dev server exposes esbuild for HMR). Not exploitable in production builds:

```json
{
  "exceptions": [
    { "id": 1098341, "reason": "esbuild SSRF — only exploitable via Vite dev server, not in production builds" }
  ]
}
```

### svelte production dep surface

For a typical Svelte SPA, the production dependency tree is very small:
- `svelte` — framework runtime
- Any routing library (`svelte-routing` or similar)
- Any state library if not using built-in stores

Audit these strictly — any advisory on `svelte` itself is high priority.

## Additional Dos

- Audit `svelte` production package separately from the Vite/build toolchain: `npm audit --omit=dev`.
- Treat any advisory on `svelte` runtime as high priority regardless of reported severity.

## Additional Don'ts

- Don't ignore advisories on `svelte` itself — the framework is a production runtime dependency.
- Don't conflate Svelte standalone advisories with SvelteKit advisories — different dependency trees and different risk profiles.
