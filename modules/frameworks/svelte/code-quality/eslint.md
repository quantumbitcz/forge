# Svelte + eslint

> Extends `modules/code-quality/eslint.md` with Svelte 5-specific integration.
> Generic eslint conventions (flat config, TypeScript setup, CI integration) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev eslint eslint-plugin-svelte svelte-eslint-parser typescript-eslint
```

**`eslint.config.js` for Svelte 5 + TypeScript:**
```js
import tseslint from "typescript-eslint";
import sveltePlugin from "eslint-plugin-svelte";
import svelteParser from "svelte-eslint-parser";

export default tseslint.config(
  ...tseslint.configs.recommendedTypeChecked,
  ...sveltePlugin.configs["flat/recommended"],
  {
    files: ["**/*.svelte"],
    languageOptions: {
      parser: svelteParser,
      parserOptions: {
        parser: tseslint.parser,
        project: "./tsconfig.json",
        extraFileExtensions: [".svelte"],
        svelteFeatures: { runes: true },   // Svelte 5 runes mode
      },
    },
  },
  {
    rules: {
      "svelte/valid-compile": "error",
      "svelte/no-unused-svelte-ignore": "error",
      "svelte/prefer-writable-derived": "error",
    },
  }
);
```

## Framework-Specific Patterns

### Svelte 5 runes awareness

Enable `svelteFeatures: { runes: true }` in parser options — without it, `$state`, `$derived`, `$effect`, `$props` are flagged as invalid:

```svelte
<script lang="ts">
  // Svelte 5 runes — requires runes: true in parser config
  let count = $state(0);
  const double = $derived(count * 2);
</script>
```

### `svelte/valid-compile`

`svelte/valid-compile` catches compile errors that the Svelte compiler would catch — run it as part of linting to surface issues before the build step:

```svelte
<!-- svelte/valid-compile error: each block expects an iterable -->
{#each nonIterable as item}
```

### `$effect` and reactive dependency lint

Svelte 5's `$effect` doesn't have an exhaustive-deps rule equivalent to React's hooks. Use `svelte/prefer-writable-derived` to avoid `$effect` for derived values:

```svelte
<!-- BAD — use $derived instead -->
<script>
  let double = $state(0);
  $effect(() => { double = count * 2; });
</script>

<!-- GOOD -->
<script>
  const double = $derived(count * 2);
</script>
```

## Additional Dos

- Set `svelteFeatures: { runes: true }` for Svelte 5 projects — required for rune syntax to parse correctly.
- Enable `svelte/no-unused-svelte-ignore` to prevent accumulation of stale `<!-- svelte-ignore -->` directives.

## Additional Don'ts

- Don't apply `@typescript-eslint` rules directly to `.svelte` files without `svelte-eslint-parser` — TypeScript rules require the Svelte-aware parser to extract script blocks.
- Don't use `eslint-plugin-svelte` v1 with Svelte 5 — only v2+ supports runes syntax.
