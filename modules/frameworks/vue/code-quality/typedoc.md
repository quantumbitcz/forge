# Vue + typedoc

> Extends `modules/code-quality/typedoc.md` with Vue-specific integration.
> Generic typedoc conventions (installation, `typedoc.json`, entryPoints) are NOT repeated here.

## Integration Setup

TypeDoc documents TypeScript code — it processes `.vue` files only for their `<script setup>` TypeScript blocks. For full Vue component documentation (including templates), consider VitePress or Storybook alongside TypeDoc.

```bash
npm install --save-dev typedoc typedoc-plugin-vue
```

**`typedoc.json` for a Vue component library:**
```json
{
  "$schema": "https://typedoc.org/schema.json",
  "entryPoints": ["src/index.ts"],
  "entryPointStrategy": "expand",
  "out": "docs/api",
  "tsconfig": "./tsconfig.app.json",
  "excludePrivate": true,
  "excludeInternal": true,
  "name": "My Vue Library",
  "plugin": ["typedoc-plugin-vue"]
}
```

## Framework-Specific Patterns

### Component documentation via exported types

Document component props and emits by exporting their interface:

```ts
// src/components/MyButton/types.ts
/** Props for the primary button component. */
export interface MyButtonProps {
  /** Button label text. */
  label: string;
  /** Visual variant. Defaults to `"primary"`. */
  variant?: "primary" | "secondary";
}
```

### Composable documentation

Composables are the primary TypeDoc target in Vue apps — they contain pure TypeScript logic:

```ts
/**
 * Provides reactive pagination state for list views.
 * @param pageSize - Number of items per page. Defaults to 20.
 * @returns Reactive pagination state and navigation helpers.
 */
export function usePagination(pageSize = 20): PaginationState { ... }
```

### App vs. library strategy

- **Libraries (npm-published):** TypeDoc on public API (`src/index.ts`)
- **Applications:** Use VitePress with `vitepress-plugin-autodoc` or Storybook — TypeDoc is insufficient for visual component documentation

## Additional Dos

- Export prop types from a `types.ts` alongside each component — TypeDoc extracts these clearly.
- Document all composables in `src/composables/` — these are the most reusable units worth documenting.

## Additional Don'ts

- Don't expect TypeDoc to render Vue template documentation — templates require specialized tools (Storybook, Histoire).
- Don't include `src/stores/` (Pinia stores) in TypeDoc entryPoints for apps — these are internal implementation details.
