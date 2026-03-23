# SvelteKit Framework Conventions

> Framework-specific conventions for SvelteKit projects. Language idioms are in `modules/languages/typescript.md`. Generic testing patterns are in `modules/testing/vitest.md`.

## Architecture (File-Based Routing)

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

**Dependency rule:** Components in `src/lib/` must not import from `src/routes/`. Pages import from `src/lib/`, never the reverse.

## Svelte 5 Runes

All new code must use runes. No old reactive syntax.

| Rune | Purpose | Replaces |
|------|---------|----------|
| `$state(value)` | Declare reactive state | `let x = value` (reactive) |
| `$derived(expr)` | Computed value from state | `$: x = expr` |
| `$effect(() => { ... })` | Side effect on state change | `$: { ... }` |
| `$props()` | Declare component props | `export let prop` |
| `$bindable()` | Declare bindable prop | `export let prop` (with bind:) |
| `$inspect(value)` | Debug reactive values (dev only) | `$: console.log(value)` |

### Shared Reactive State (`.svelte.ts` files)

For cross-component state, use `.svelte.ts` files with `$state` and getter/setter pattern.
Do **not** use `writable()` / `readable()` / `derived()` from `svelte/store` in new Svelte 5 code.

## Component Patterns

- Use `$props()` with destructured typed object for props
- Callback props (e.g., `onSelect`) instead of `createEventDispatcher`
- Spread rest props: `let { class: className, ...rest } = $props()`
- Use `{#snippet}` for reusable template fragments (replaces slots for advanced use)

## Naming Patterns

| Artifact | Pattern | Notes |
|----------|---------|-------|
| Component | `PascalCase.svelte` | In `src/lib/components/` |
| Store / state | `camelCase.svelte.ts` | In `src/lib/stores/` |
| Utility | `camelCase.ts` | In `src/lib/utils/` |
| Test | `*.test.ts` or `*.spec.ts` | Co-located or in `tests/` |

## Code Quality

- Components: max ~100 lines of template, max ~50 lines of script
- Functions: max ~30 lines, max 3 nesting levels
- `$effect` must return a cleanup function if it creates subscriptions/timers
- No old Svelte 3/4 reactive syntax (`$:`, `export let`, `createEventDispatcher`)

## Styling

- Scoped styles in `<style>` blocks (Svelte default)
- Tailwind CSS utility classes where configured
- CSS custom properties for theming: `var(--color-primary)`
- Component variants via props, not global CSS overrides

## Load Functions and Form Actions

### Load Functions
- Return plain objects (serializable data)
- Use `depends()` for granular invalidation
- Access auth state via `locals` (set in hooks)
- Type-safe with generated `$types`

### Form Actions
- Use `<form method="POST">` with `+page.server.ts` actions for mutations
- Use `use:enhance` for progressive enhancement
- Return `fail(400, { error: '...' })` for validation errors
- Redirect with `redirect(303, '/path')`

## Error Handling

- Page-level: `+error.svelte` error boundaries
- Load functions: throw `error(status, message)` from `@sveltejs/kit`
- Form actions: return `fail(status, data)` for validation errors
- Global: `handleError` hook in `hooks.server.ts`

## Security

- Sensitive logic in `+page.server.ts` or `src/lib/server/` -- never in client-accessible code
- CSRF protection: built-in with SvelteKit form actions
- Auth: validate session in `hooks.server.ts`, set `locals.user`
- Environment variables: `$env/static/private` for secrets, `$env/static/public` for public values

## Accessibility

- All interactive elements keyboard-accessible (Tab, Enter, Escape, Arrow keys)
- Form inputs need associated `<label>` elements (or `aria-label`)
- Color contrast: minimum 4.5:1 for normal text, 3:1 for large text (WCAG AA)
- Use semantic HTML: `<nav>`, `<main>`, `<article>`, `<section>`, `<button>`

## Performance

- Use `<img loading="lazy">` for below-fold images
- Code split at route level (SvelteKit does this automatically)
- Use `$effect.pre()` for DOM measurements before paint
- Prefer `{#each items as item (item.id)}` with keyed blocks for list identity
- Use `{@html}` sparingly and ONLY with sanitized content (XSS risk)

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Dos and Don'ts

### Do
- Use `$state()` for reactive state, `$derived()` for computed values
- Use `$effect()` with cleanup for side effects
- Prefer snippet-based composition (`{@render}`) over slot-based for new components
- Implement loading, error, and empty states for every data-fetching component
- Use form actions for mutations -- progressive enhancement works without JS

### Don't
- Don't use `$:` reactive statements -- use `$derived()` or `$effect()`
- Don't use `export let` for props -- use `$props()`
- Don't use `onMount`/`onDestroy` -- use `$effect()` with cleanup
- Don't fetch data in components -- use load functions
- Don't use `goto()` for data refresh -- use `invalidateAll()` or `invalidate('tag')`
- Don't put secrets in `+page.ts` -- only `+page.server.ts` runs server-side
