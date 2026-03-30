# typedoc

## Overview

TypeDoc generates API documentation from TypeScript source files using TSDoc-style comments. Install via `npm install --save-dev typedoc`. Configure through `typedoc.json` or the `typedocOptions` key in `tsconfig.json`. Use `--entryPoints` to specify the public API surface. The `typedoc-plugin-markdown` plugin outputs Markdown instead of HTML for integration with Docusaurus, VitePress, or similar doc sites.

## Architecture Patterns

### Installation & Setup

```bash
npm install --save-dev typedoc
# Markdown output plugin (optional)
npm install --save-dev typedoc-plugin-markdown
# Mermaid diagram support (optional)
npm install --save-dev typedoc-plugin-mermaid
```

**`typedoc.json` configuration:**
```json
{
  "$schema": "https://typedoc.org/schema.json",
  "entryPoints": ["src/index.ts"],
  "entryPointStrategy": "expand",
  "out": "docs/api",
  "tsconfig": "./tsconfig.json",
  "name": "My Library",
  "readme": "README.md",
  "includeVersion": true,
  "excludePrivate": true,
  "excludeProtected": false,
  "excludeInternal": true,
  "excludeExternals": true,
  "validation": {
    "invalidLink": true,
    "notExported": true
  },
  "categorizeByGroup": true,
  "sort": ["source-order"]
}
```

**Multi-package (monorepo) entry points:**
```json
{
  "entryPoints": ["packages/core/src/index.ts", "packages/client/src/index.ts"],
  "entryPointStrategy": "packages"
}
```

### Rule Categories

| Category | Pattern | Pipeline Severity |
|---|---|---|
| Missing `@param` tag | Exported function param without TSDoc | INFO |
| Missing `@returns` tag | Exported non-void function without `@returns` | INFO |
| Broken `{@link}` | Reference to non-exported or non-existent symbol | WARNING |
| `@internal` on exported | Symbol tagged `@internal` but re-exported | WARNING |
| No entry point doc | `index.ts` without module-level comment | INFO |

### Configuration Patterns

**TSDoc comment syntax:**
```typescript
/**
 * Parses a raw CSV string into an array of typed records.
 *
 * @remarks
 * The first row is treated as headers. Empty lines are skipped.
 * Throws on malformed rows unless `options.skipErrors` is true.
 *
 * @param csv - The raw CSV string to parse.
 * @param options - Parsing configuration.
 * @returns An array of records keyed by header names.
 *
 * @throws {@link ParseError} if a row cannot be parsed and `skipErrors` is false.
 *
 * @example
 * ```ts
 * const records = parseCsv("name,age\nAlice,30");
 * // [{ name: "Alice", age: "30" }]
 * ```
 *
 * @since 1.2.0
 * @public
 */
export function parseCsv(csv: string, options?: ParseOptions): Record<string, string>[]
```

**Hiding internal symbols:**
```typescript
/** @internal */
export function _unsafeReset(): void {}  // excluded via excludeInternal: true
```

**`typedoc-plugin-markdown` for Docusaurus:**
```json
{
  "plugin": ["typedoc-plugin-markdown"],
  "out": "docs/api",
  "outputFileStrategy": "modules",
  "flattenOutputFiles": false,
  "indexFormat": "table"
}
```

**Custom category annotations:**
```typescript
/**
 * @categoryDescription Core Utilities
 * Low-level helpers used across all modules.
 *
 * @module
 */
```

### CI Integration

```yaml
# .github/workflows/docs.yml
- name: Generate TypeDoc
  run: npx typedoc --validation.invalidLink

- name: Fail on broken links
  run: npx typedoc --validation.invalidLink --treatWarningsAsErrors

- name: Deploy to GitHub Pages
  uses: peaceiris/actions-gh-pages@v4
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./docs/api
```

```json
// package.json scripts
{
  "scripts": {
    "docs": "typedoc",
    "docs:check": "typedoc --emit none"
  }
}
```

## Performance

- TypeDoc builds the full TypeScript compiler program — slow for large projects (15-60s). Run it only on publish/release branches, not on every PR.
- `entryPointStrategy: "expand"` (processes all files in the directory tree) is slower than `"resolve"` (only processes explicitly listed entry points). Use `"resolve"` for libraries with a single barrel `index.ts`.
- Use `--emit none` in CI checks to verify without writing output (faster).
- Exclude test files and fixtures via `exclude` patterns in `typedoc.json`:
  ```json
  { "exclude": ["**/*.test.ts", "**/__fixtures__/**"] }
  ```

## Security

- TypeDoc generates static HTML/Markdown — no runtime security surface.
- `@remarks` and `@example` blocks support raw Markdown/HTML. Avoid including user-provided content in comments compiled into public docs.
- TypeDoc resolves all exported symbols — accidentally exporting internal modules exposes their documentation publicly. Use `excludeInternal: true` paired with `@internal` tags.

## Testing

```bash
# Generate HTML docs
npx typedoc

# Validate without writing output
npx typedoc --emit none

# Fail on broken cross-references
npx typedoc --validation.invalidLink --treatWarningsAsErrors

# Generate Markdown output
npx typedoc --plugin typedoc-plugin-markdown

# Watch mode for local development
npx typedoc --watch

# Print resolved config
npx typedoc --showConfig
```

## Dos

- Specify `entryPoints` explicitly to control exactly what surfaces in the public API docs.
- Enable `validation.invalidLink: true` in CI — broken `{@link}` references are a common source of confusing docs.
- Use TSDoc tags (`@param`, `@returns`, `@throws`, `@example`) consistently — TypeDoc renders them in structured sections.
- Mark implementation details with `@internal` and set `excludeInternal: true` so they don't appear in published output.
- Set `includeVersion: true` to embed the package version in the generated docs title.
- Use `typedoc-plugin-markdown` when embedding API docs in a documentation site (Docusaurus, VitePress) to keep a single source of truth.

## Don'ts

- Don't use JSDoc-style `/** @type {Foo} */` annotations in TypeScript — TypeDoc reads TypeScript types directly; redundant `@type` tags create noise.
- Don't run TypeDoc on every PR without caching — it re-invokes the TypeScript compiler and is expensive.
- Don't rely on TypeDoc to enforce documentation coverage — it only generates docs for what exists. Pair with a TSDoc coverage lint rule to enforce completeness.
- Don't export internal implementation modules just to document them — use `@internal` and the `exclude` pattern instead.
- Don't skip `@throws` on functions that reject Promises or throw synchronously — it is the primary contract signal for error handling.
- Don't use `--entryPointStrategy resolve` with re-export barrels that don't fully surface the API — hidden symbols will be omitted from docs silently.
