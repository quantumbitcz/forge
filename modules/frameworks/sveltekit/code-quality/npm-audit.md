# SvelteKit + npm-audit

> Extends `modules/code-quality/npm-audit.md` with SvelteKit-specific integration.
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

### SvelteKit server-side production risk

Unlike standalone Svelte SPAs, SvelteKit runs server-side code in production (Nitro adapter, Node.js adapter, Vercel edge). Server-side dependencies carry real exploit surface — audit more strictly than a pure SPA:

```bash
# SvelteKit — include moderate because server code is production runtime
npm audit --audit-level=moderate
```

### Adapter-specific production deps

Different SvelteKit adapters add production dependencies:

| Adapter | Production packages |
|---|---|
| `@sveltejs/adapter-node` | Node.js built-ins only |
| `@sveltejs/adapter-vercel` | Vercel edge runtime |
| `@sveltejs/adapter-cloudflare` | Cloudflare Workers runtime |

Audit the adapter package and its dependencies explicitly:

```bash
npm audit --json | jq '.vulnerabilities | to_entries[] | select(.value.name | startswith("@sveltejs/adapter"))'
```

### `svelte`, `@sveltejs/kit`, `vite` separation

- `svelte` and `@sveltejs/kit` are both production runtime packages — any advisory is high priority.
- `vite` is a devDependency (build tool) — `--omit=dev` excludes it from production gates.

### Dependency update cadence

SvelteKit releases frequently. Keep `@sveltejs/kit` updated to avoid accumulating known vulnerability windows:

```bash
npx svelte-migrate kit  # apply breaking change migrations
npm update @sveltejs/kit svelte
```

## Additional Dos

- Use `--audit-level=moderate` for SvelteKit projects — server-side code has real exploit surface.
- Audit after every `@sveltejs/kit` major version upgrade — breaking changes often coincide with dependency refreshes.

## Additional Don'ts

- Don't treat SvelteKit as a pure SPA for security auditing purposes — server routes and hooks run in production Node.js/edge environments.
- Don't skip auditing `@sveltejs/kit` itself — the framework includes server request handling and auth middleware hooks.
