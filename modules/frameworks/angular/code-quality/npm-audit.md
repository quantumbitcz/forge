# Angular + npm-audit

> Extends `modules/code-quality/npm-audit.md` with Angular-specific integration.
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

### Angular CLI devDependency noise

Angular projects have large devDependency trees (Angular CLI, builders, compilers). Many advisories in `@angular-devkit/*` are build-tool vulnerabilities not reachable from the browser bundle. Scope CI gates to `--omit=dev`:

```yaml
# .github/workflows/security.yml
- name: Audit production deps
  run: npm audit --omit=dev --audit-level=high
```

### Zone.js and RxJS

Zone.js and RxJS are production dependencies with historically few advisories. Monitor them specifically:

```bash
npm audit --json | jq '.vulnerabilities | to_entries[] | select(.value.name == "zone.js" or .value.name == "rxjs")'
```

### Angular Material transitive deps

Angular Material pulls in `@angular/cdk` and `hammerjs` (v13 and earlier). Post-Angular 14 projects using only Angular Material should have minimal production advisories:

```bash
# Check only production tree depth
npm audit --omit=dev --json | jq '.metadata.vulnerabilities'
```

### Dependency update strategy

Angular follows a predictable major release cadence (2x/year). Use `ng update` rather than `npm audit fix --force` for Angular packages — the Angular CLI migration scripts handle breaking changes:

```bash
npx ng update @angular/core @angular/cli
```

## Additional Dos

- Use `ng update` for Angular core packages — it runs schematics to update code alongside the package version.
- Schedule weekly `npm audit --omit=dev` in CI separate from the main build to avoid blocking deployments on advisory noise.

## Additional Don'ts

- Don't apply `npm audit fix --force` to Angular packages — the Angular CLI `ng update` command handles migrations correctly.
- Don't ignore high-severity advisories in `@angular/core` or `@angular/common` — these are production runtime dependencies.
