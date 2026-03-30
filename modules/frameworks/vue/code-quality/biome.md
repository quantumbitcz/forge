# Vue + biome

> Extends `modules/code-quality/biome.md` with Vue-specific integration.
> Generic biome conventions (installation, rule categories, CI integration) are NOT repeated here.

## Integration Setup

Biome does NOT support `.vue` SFC files — the Vue single-file component format uses a custom block structure that Biome cannot parse. Use Biome for standalone `.ts` files and `eslint-plugin-vue` for `.vue` files:

```json
{
  "$schema": "https://biomejs.org/schemas/1.9.4/schema.json",
  "files": {
    "include": ["src/**/*.ts"],
    "ignore": ["src/**/*.d.ts", "**/*.vue"]
  },
  "linter": {
    "rules": {
      "correctness": { "recommended": true },
      "suspicious": { "recommended": true }
    }
  }
}
```

## Framework-Specific Patterns

### Biome + eslint-plugin-vue split

Run Biome on TypeScript utility/composable files; run ESLint with `eslint-plugin-vue` on `.vue` files:

```json
// package.json scripts
{
  "lint:ts": "biome check src/**/*.ts",
  "lint:vue": "eslint src/**/*.vue",
  "lint": "npm run lint:ts && npm run lint:vue"
}
```

### Composables are the primary Biome target

Vue composables (`src/composables/*.ts`) are pure TypeScript with no Vue SFC syntax — these are the highest-value Biome target:

```ts
// src/composables/useCounter.ts — pure TS, linted by Biome
export function useCounter(initial = 0) {
  const count = ref(initial);
  const increment = () => count.value++;
  return { count, increment };
}
```

### Pinia store files

Pinia store files are pure TypeScript — include them explicitly:

```json
{
  "files": {
    "include": ["src/**/*.ts", "src/stores/**/*.ts"]
  }
}
```

## Additional Dos

- Apply Biome's import sorting to `.ts` files alongside `eslint-plugin-vue`'s import rules for `.vue` files.
- Use Biome for formatting `.ts` files; use Prettier with `prettier-plugin-vue` for `.vue` files — configure them to use consistent settings.

## Additional Don'ts

- Don't apply Biome to `.vue` files — it will throw parse errors on `<template>`, `<script setup>`, and `<style>` blocks.
- Don't replace `eslint-plugin-vue` entirely with Biome — Vue-specific template and SFC rules require the Vue plugin.
