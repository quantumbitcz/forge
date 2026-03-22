# TypeScript/SvelteKit Agent Conventions Reference

> Full details in project CLAUDE.md. This is a curated subset for agent consumption.

## Architecture (SvelteKit File-Based Routing)

| Concept | Responsibility | Location |
|---------|---------------|----------|
| Page | Route UI component | `src/routes/**/+page.svelte` |
| Layout | Shared layout wrapper | `src/routes/**/+layout.svelte` |
| Server load | Server-side data fetching | `src/routes/**/+page.server.ts` |
| Universal load | Shared data fetching (SSR + client) | `src/routes/**/+page.ts` |
| Form action | Server-side form handling | `src/routes/**/+page.server.ts` (actions) |
| API route | REST-like endpoints | `src/routes/api/**/+server.ts` |
| Component | Reusable UI component | `src/lib/components/` |
| Store / state | Shared reactive state | `src/lib/stores/` or `$state` in `.svelte.ts` |
| Server utility | Server-only helpers | `src/lib/server/` |

**Dependency rule:** Components in `src/lib/` are reusable and must not import from `src/routes/`. Pages import from `src/lib/`, never the reverse.

## Svelte 5 Runes

Svelte 5 replaces the old reactive syntax with runes. All new code must use runes.

### Core Runes

| Rune | Purpose | Replaces |
|------|---------|----------|
| `$state(value)` | Declare reactive state | `let x = value` (reactive) |
| `$derived(expr)` | Computed value from state | `$: x = expr` |
| `$effect(() => { ... })` | Side effect on state change | `$: { ... }` (reactive statements) |
| `$props()` | Declare component props | `export let prop` |
| `$bindable()` | Declare bindable prop | `export let prop` (with bind:) |
| `$inspect(value)` | Debug reactive values (dev only) | `$: console.log(value)` |

### State Management

```svelte
<script lang="ts">
  // Component state
  let count = $state(0);
  let doubled = $derived(count * 2);

  // Props
  let { title, onClose }: { title: string; onClose: () => void } = $props();

  // Side effect with cleanup
  $effect(() => {
    const interval = setInterval(() => count++, 1000);
    return () => clearInterval(interval);
  });
</script>
```

### Shared Reactive State (`.svelte.ts` files)

For cross-component state, use `.svelte.ts` files:

```typescript
// src/lib/stores/counter.svelte.ts
export function createCounter(initial = 0) {
  let count = $state(initial);
  return {
    get count() { return count; },
    increment() { count++; },
    decrement() { count--; },
  };
}
```

**Do not use** `writable()` / `readable()` / `derived()` from `svelte/store` in new Svelte 5 code — use `$state` and `$derived` runes instead.

## SvelteKit Routing

### File Conventions

| File | Purpose |
|------|---------|
| `+page.svelte` | Page component (renders UI) |
| `+page.ts` | Universal load function (runs on server + client) |
| `+page.server.ts` | Server-only load function + form actions |
| `+layout.svelte` | Layout component (wraps child pages) |
| `+layout.ts` | Universal layout load function |
| `+layout.server.ts` | Server-only layout load function |
| `+server.ts` | API endpoint (GET, POST, PUT, DELETE) |
| `+error.svelte` | Error boundary page |

### Load Functions

```typescript
// +page.server.ts
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ params, locals, fetch }) => {
  const item = await db.getItem(params.id);
  if (!item) throw error(404, 'Not found');
  return { item };
};
```

- Load functions return plain objects (serializable data)
- Use `depends()` for granular invalidation
- Access auth state via `locals` (set in hooks)
- Type-safe with generated `$types`

### Form Actions

```typescript
// +page.server.ts
import type { Actions } from './$types';

export const actions: Actions = {
  create: async ({ request, locals }) => {
    const data = await request.formData();
    // validate & process
    return { success: true };
  },
};
```

- Use `enhance` for progressive enhancement: `<form method="POST" action="?/create" use:enhance>`
- Return `fail(400, { error: '...' })` for validation errors
- Redirect with `redirect(303, '/path')`

## Component Patterns

### Props and Events

```svelte
<script lang="ts">
  let { items, onSelect, class: className = '' }: {
    items: Item[];
    onSelect: (item: Item) => void;
    class?: string;
  } = $props();
</script>
```

- Use `$props()` with destructured typed object
- Callback props (e.g., `onSelect`) instead of `createEventDispatcher`
- Optional props with default values in destructuring
- Spread rest props: `let { class: className, ...rest } = $props()`

### Snippets (Svelte 5)

Use `{#snippet}` for reusable template fragments (replaces slots for advanced use):

```svelte
{#snippet header()}
  <h1>Title</h1>
{/snippet}

<Card {header} />
```

## Naming Patterns

| Artifact | Pattern | Notes |
|----------|---------|-------|
| Page | `+page.svelte` | File-based routing |
| Layout | `+layout.svelte` | Nested layouts |
| Component | `PascalCase.svelte` | In `src/lib/components/` |
| Server load | `+page.server.ts` | Server-side only |
| Store / state | `camelCase.svelte.ts` | In `src/lib/stores/` |
| Utility | `camelCase.ts` | In `src/lib/utils/` |
| API route | `+server.ts` | REST endpoints |
| Test | `*.test.ts` or `*.spec.ts` | Co-located or in `tests/` |

## Project Structure

```
src/
  routes/                   # File-based routing
    (app)/                  # Route group (layout grouping)
      dashboard/
        +page.svelte
        +page.server.ts
      +layout.svelte
    api/                    # API endpoints
      items/+server.ts
    +layout.svelte          # Root layout
    +page.svelte            # Home page
  lib/
    components/             # Reusable Svelte components
    server/                 # Server-only utilities (DB, auth)
    stores/                 # Shared state (.svelte.ts files)
    utils/                  # Shared utilities
    types/                  # TypeScript type definitions
  hooks.server.ts           # Server hooks (auth, logging)
  app.html                  # HTML template
  app.d.ts                  # App-level type declarations
```

## Code Quality

- Components: max ~100 lines of template, max ~50 lines of script
- Functions: max ~30 lines, max 3 nesting levels
- `$effect` must return a cleanup function if it creates subscriptions/timers
- No old Svelte 3/4 reactive syntax (`$:`, `export let`, `createEventDispatcher`)
- TypeScript strict mode: `strict: true` in tsconfig
- No `any` types unless explicitly justified
- Prefer `const` over `let`; never use `var`

## Styling

- Scoped styles in `<style>` blocks (Svelte default)
- Tailwind CSS utility classes where configured
- CSS custom properties for theming: `var(--color-primary)`
- No inline styles unless dynamic values require them
- Component variants via props, not global CSS overrides

## Testing

- **Unit tests:** Vitest + `@testing-library/svelte` for component testing
- **Integration tests:** Playwright for E2E
- **Load function tests:** Direct import and call with mocked event
- **Naming:** `describe('ComponentName', () => { it('should do X when Y', ...) })`
- **Rules:** Test behavior not implementation, one logical assertion per test

## Error Handling

- Page-level: `+error.svelte` error boundaries
- Load functions: throw `error(status, message)` from `@sveltejs/kit`
- Form actions: return `fail(status, data)` for validation errors
- API routes: return `json({ error }, { status })` or throw `error()`
- Global: `handleError` hook in `hooks.server.ts`

## Security

- Sensitive logic in `+page.server.ts` or `src/lib/server/` — never in client-accessible code
- CSRF protection: built-in with SvelteKit form actions
- Auth: validate session in `hooks.server.ts`, set `locals.user`
- Never trust client-side data — always validate on server
- Environment variables: `$env/static/private` for secrets, `$env/static/public` for public values

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated files, changing APIs, fixing pre-existing bugs.

## Dos and Don'ts

### Do
- Use `$state()` rune for reactive state, `$derived()` for computed values (Svelte 5+)
- Use `$effect()` with cleanup for side effects (timers, subscriptions, event listeners)
- Prefer snippet-based composition (`{@render}`) over slot-based for new components
- Use `$props()` with TypeScript types for component props
- Implement loading, error, and empty states for every data-fetching component
- Use `+page.server.ts` for server-side data loading, `+page.ts` for universal
- Use form actions for mutations — progressive enhancement works without JS

### Don't
- Don't use `$:` reactive statements — use `$derived()` or `$effect()` runes (Svelte 5)
- Don't use `export let` for props — use `$props()` rune (Svelte 5)
- Prefer reassignment over deep mutation for `$state()` objects — Svelte 5 does track deep mutations via proxies, but explicit reassignment makes intent clearer and is easier to debug
- Don't use `onMount`/`onDestroy` — use `$effect()` with cleanup function
- Don't fetch data in components — use load functions in `+page.ts` / `+page.server.ts`
- Don't use `goto()` for data refresh — use `invalidateAll()` or `invalidate('tag')`
- Don't put secrets in `+page.ts` — only `+page.server.ts` runs server-side

## API Integration

### Data Loading
- **Server-side:** `+page.server.ts` `load()` for authenticated/sensitive data
- **Universal:** `+page.ts` `load()` for public data that benefits from client-side navigation
- **Client-only:** `$effect()` with fetch for real-time data (polling, WebSockets)
- Always return typed data from load functions — define types in `$types.d.ts` or shared types file

### Form Actions
- Use `<form method="POST">` with `+page.server.ts` actions for mutations
- Use `use:enhance` for progressive enhancement (works without JS, enhances with JS)
- Return validation errors from actions — display inline with `form.errors`
- Redirect after successful mutation to prevent resubmission

### Error Handling
- Use `+error.svelte` for route-level error pages
- Throw `error(404, 'Not found')` from load functions for expected errors
- Catch unexpected errors in `handleError` hook (`hooks.server.ts`)
- Display user-friendly messages — never expose stack traces

## Accessibility

### Requirements
- All interactive elements must be keyboard-accessible (Tab, Enter, Escape, Arrow keys)
- All images need `alt` text (empty `alt=""` for decorative images)
- Form inputs need associated `<label>` elements (or `aria-label`)
- Color contrast: minimum 4.5:1 for normal text, 3:1 for large text (WCAG AA)
- Use semantic HTML: `<nav>`, `<main>`, `<article>`, `<section>`, `<button>` (not `<div onclick>`)

### Testing Accessibility
- Use `@testing-library/svelte` with `getByRole`, `getByLabelText` queries
- Run axe-core in tests: `@axe-core/playwright` for E2E
- Test with keyboard only (no mouse) for critical flows

## Performance

### Loading Optimization
- Use `<img loading="lazy">` for below-fold images
- Preload critical fonts with `<link rel="preload">`
- Code split at route level (SvelteKit does this automatically)
- Use `$effect.pre()` for DOM measurements that must happen before paint

### Rendering Optimization
- Use `{#key expression}` to force re-render when identity changes (not just content)
- Prefer `{#each items as item (item.id)}` with keyed blocks for list identity
- Avoid expensive computations in `$derived()` — use `$derived.by()` for complex logic with caching
- Use `{@html}` sparingly and ONLY with sanitized content (XSS risk)

## Dependency Management

### Package Manager
- Use pnpm for faster installs and strict dependency resolution
- Lock file (`pnpm-lock.yaml`) must be committed
- Review `pnpm audit` results before adding new dependencies
- Prefer `devDependencies` for build-only tools (Vite plugins, test libraries)

### Choosing Dependencies
- Check: last commit date, open issues, weekly downloads, bundle size (bundlephobia.com)
- Prefer Svelte-native packages over React-wrapper ports
- For utilities < 20 lines: write your own instead of importing a package
