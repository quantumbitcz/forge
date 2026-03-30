# SvelteKit + biome

> Extends `modules/code-quality/biome.md` with SvelteKit-specific integration.
> Generic biome conventions (installation, rule categories, CI integration) are NOT repeated here.

## Integration Setup

Biome does NOT support `.svelte` files. Apply Biome to SvelteKit's TypeScript server and utility files; use `eslint-plugin-svelte` for `.svelte` components:

```json
{
  "$schema": "https://biomejs.org/schemas/1.9.4/schema.json",
  "files": {
    "include": ["src/**/*.ts", "src/**/*.js"],
    "ignore": ["**/*.svelte", ".svelte-kit/**", "build/**", "**/*.d.ts"]
  },
  "linter": {
    "rules": {
      "correctness": { "recommended": true },
      "suspicious": { "recommended": true },
      "style": { "recommended": true }
    }
  }
}
```

## Framework-Specific Patterns

### SvelteKit server file coverage

SvelteKit's server files are pure TypeScript — highest-value Biome target:

```
src/hooks.server.ts           → Biome
src/hooks.client.ts           → Biome
src/routes/**/+page.server.ts → Biome
src/routes/**/+layout.server.ts → Biome
src/lib/server/**/*.ts        → Biome
```

### `$lib` import alias

SvelteKit uses `$lib` for `src/lib/` imports. Configure Biome's import organizer to treat `$lib` as a project-local import (not external):

```json
{
  "assist": {
    "actions": {
      "source": {
        "organizeImports": { "enabled": true }
      }
    }
  }
}
```

### Promise handling in server routes

Biome's `correctness/noFloatingPromises` (when available) is especially important for `+page.server.ts` load functions. Until Biome supports this rule, rely on `@typescript-eslint/no-floating-promises` for server files.

## Additional Dos

- Apply Biome to all `*.server.ts` and `src/lib/server/**/*.ts` files — server-side logic is pure TS with no Svelte template complications.
- Exclude `.svelte-kit/` from Biome's scope — it regenerates on every dev server restart.

## Additional Don'ts

- Don't include `.svelte` files in Biome's `include` — they will fail to parse.
- Don't skip Biome on server files to compensate for lack of `.svelte` support — server files are the highest-value TypeScript in a SvelteKit project.
