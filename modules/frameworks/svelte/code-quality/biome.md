# Svelte + biome

> Extends `modules/code-quality/biome.md` with Svelte-specific integration.
> Generic biome conventions (installation, rule categories, CI integration) are NOT repeated here.

## Integration Setup

Biome does NOT support `.svelte` files — use Biome for TypeScript modules and `eslint-plugin-svelte` for `.svelte` components:

```json
{
  "$schema": "https://biomejs.org/schemas/1.9.4/schema.json",
  "files": {
    "include": ["src/**/*.ts", "src/**/*.js"],
    "ignore": ["**/*.svelte", "**/*.d.ts"]
  },
  "linter": { "rules": { "recommended": true } },
  "formatter": { "indentStyle": "tab", "lineWidth": 100 }
}
```

## Framework-Specific Patterns

### Biome scope in Svelte projects

Svelte projects typically have a thin TypeScript layer (stores, utilities) and a larger `.svelte` component layer. Biome's value is concentrated on the TypeScript layer:

```
src/lib/          → Biome (pure TS utilities, stores)
src/routes/       → eslint-plugin-svelte (.svelte files)
src/components/   → eslint-plugin-svelte (.svelte files)
```

### Svelte stores as Biome targets

Svelte stores (`writable`, `derived`, `readable`) are pure TypeScript — full Biome coverage:

```ts
// src/lib/stores/counter.ts — full Biome linting
import { writable, derived } from "svelte/store";
export const count = writable(0);
export const doubled = derived(count, ($c) => $c * 2);
```

### Tab vs. space indentation

The Svelte community defaults to tabs for indentation. Configure Biome to match:

```json
{
  "formatter": { "indentStyle": "tab" }
}
```

## Additional Dos

- Apply Biome to `src/lib/**/*.ts` only — utilities and stores where pure TS logic lives.
- Align Biome's `indentStyle: "tab"` with `prettier-plugin-svelte` config to avoid conflicts.

## Additional Don'ts

- Don't attempt to add `.svelte` to Biome's `include` — Biome will throw parse errors on Svelte's template syntax and `$state`/`$derived` runes.
- Don't run Biome and Prettier on the same `.ts` files — pick one formatter per file type.
