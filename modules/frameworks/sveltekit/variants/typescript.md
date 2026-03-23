# SvelteKit + TypeScript Variant

> TypeScript-specific patterns for SvelteKit projects. Extends `modules/languages/typescript.md` and `modules/frameworks/sveltekit/conventions.md`.

## Component Props Typing

```svelte
<script lang="ts">
  let { items, onSelect, class: className = '' }: {
    items: Item[];
    onSelect: (item: Item) => void;
    class?: string;
  } = $props();
</script>
```

- Always use `lang="ts"` in script blocks
- Type props inline in `$props()` destructuring or extract to a named type
- Use `Snippet` type for typed snippet props

## Generated Types

- SvelteKit generates `$types` per route -- always use for load function typing
- `PageServerLoad`, `PageLoad`, `LayoutServerLoad`, `LayoutLoad` from `./$types`
- `Actions` type for form actions

```typescript
import type { PageServerLoad } from './$types';
export const load: PageServerLoad = async ({ params }) => { ... };
```

## State Typing

- `$state<Type>(initial)` for explicit generic typing when inference is insufficient
- `.svelte.ts` files: export getter/setter objects with explicit return types
- Use discriminated unions for complex state machines

## Event Handler Typing

- Callback props: type as function signatures in `$props()` destructuring
- Form events: `SubmitEvent`, `Event & { currentTarget: HTMLFormElement }`
- Use `on:event` typing from Svelte HTML attribute types

## Strict Mode

- `strict: true` in tsconfig -- no exceptions
- No `any` types unless explicitly justified
- Prefer `const` over `let`; never use `var`
- No `as` assertions except narrowing from `unknown`
