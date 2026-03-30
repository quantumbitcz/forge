# Svelte + prettier

> Extends `modules/code-quality/prettier.md` with Svelte-specific integration.
> Generic prettier conventions (installation, `.prettierrc`, CI integration) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev prettier prettier-plugin-svelte
```

**`.prettierrc` for Svelte:**
```json
{
  "useTabs": true,
  "tabWidth": 2,
  "semi": true,
  "singleQuote": true,
  "printWidth": 100,
  "trailingComma": "es5",
  "plugins": ["prettier-plugin-svelte"],
  "overrides": [
    {
      "files": "*.svelte",
      "options": { "parser": "svelte" }
    }
  ]
}
```

## Framework-Specific Patterns

### `prettier-plugin-svelte` parser

The `"parser": "svelte"` override is required — without it, Prettier treats `.svelte` files as HTML and mangles Svelte-specific syntax (`{#if}`, `{#each}`, `$state`, template expressions):

```svelte
<!-- Without parser: "svelte" — mangled output -->
<!-- With parser: "svelte" — correct formatting -->
{#each items as item (item.id)}
  <li>{item.name}</li>
{/each}
```

### Tab indentation

The Svelte community strongly prefers tabs. Aligning Prettier and ESLint on `useTabs: true` avoids tab/space conflicts in `svelte/indent` checks.

### Svelte 5 runes formatting

`prettier-plugin-svelte` v3.2+ formats Svelte 5 rune expressions (`$state`, `$derived`, `$effect`, `$props`) correctly. Ensure plugin version compatibility:

```bash
# Check versions
npm ls prettier prettier-plugin-svelte
# Svelte 5 support requires prettier-plugin-svelte >= 3.2.0
```

### `.prettierignore` for Svelte

```
build/
.svelte-kit/
node_modules/
```

## Additional Dos

- Pin `prettier-plugin-svelte` to a version that supports Svelte 5 runes (`>= 3.2.0`).
- Format both `.svelte` and `.ts` files in pre-commit: `prettier --write "src/**/*.{svelte,ts,js,css}"`.

## Additional Don'ts

- Don't omit `"parser": "svelte"` in the overrides — Prettier will treat `.svelte` as HTML and produce incorrect output.
- Don't set `useTabs: false` for Svelte projects unless the team explicitly agrees — the community convention is tabs.
