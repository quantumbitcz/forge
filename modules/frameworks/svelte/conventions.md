# Svelte 5 Framework Conventions

> Support tier: contract-verified

> Framework-specific conventions for standalone Svelte 5 projects (SPAs, widget libraries, Electron apps, Vite-based UIs). **Not SvelteKit** — no file-based routing, no server-side rendering, no load functions. Language idioms are in `modules/languages/typescript.md`. Generic testing patterns are in `modules/testing/vitest.md`.

## Architecture (Component-Based SPA)

| Layer | Responsibility | Location |
|-------|---------------|----------|
| App shell | Root component, router outlet | `src/App.svelte` |
| Page / view | Route-level component | `src/pages/` or `src/views/` |
| Feature component | Feature-specific UI + local state | `src/components/{feature}/` |
| Shared component | Reusable UI atoms/molecules | `src/components/shared/` |
| Store | Shared reactive state | `src/stores/` (`.svelte.ts` files) |
| Service | Data fetching, business logic | `src/services/` |
| Utility | Pure helper functions | `src/utils/` |
| Type definitions | Shared types/interfaces | `src/types/` |

**Dependency rule:** Shared components must not import from feature components or pages. Pages import from feature and shared components, never the reverse.

## Svelte 5 Runes

All new code must use runes. Never use old Svelte 3/4 reactive syntax.

| Rune | Purpose | Replaces |
|------|---------|----------|
| `$state(value)` | Declare reactive state | `let x = value` (reactive) |
| `$derived(expr)` | Computed value from state | `$: x = expr` |
| `$effect(() => { ... })` | Side effect on state change (with cleanup) | `$: { ... }`, `onMount`, `onDestroy` |
| `$props()` | Declare component props | `export let prop` |
| `$bindable()` | Declare a bindable prop | `export let prop` (with `bind:`) |
| `$inspect(value)` | Debug reactive values (dev only) | `$: console.log(value)` |

### Shared Reactive State (`.svelte.ts` files)

For cross-component state, use `.svelte.ts` files with `$state` runes and getter/setter pattern. Svelte stores (`writable`, `readable`, `derived` from `svelte/store`) are permitted for third-party library compatibility only — prefer rune-based state for all first-party code.

```typescript
// src/stores/user.svelte.ts
let _user = $state<User | null>(null);

export const userStore = {
  get current() { return _user; },
  set(user: User | null) { _user = user; },
  clear() { _user = null; },
};
```

## Component Patterns

- Use `$props()` with a destructured typed object for all props
- Callback props (`onSelect`, `onChange`) instead of `createEventDispatcher`
- Spread rest props for passthrough: `let { class: className = '', ...rest } = $props()`
- Use `{#snippet}` for reusable template fragments (replaces named slots for new components)
- Prefer `{@render children?.()}` over `<slot>` for content projection
- Event handlers as standard DOM event attributes: `onclick`, `oninput`, `onsubmit` (not `on:click`)

## Naming Patterns

| Artifact | Pattern | Notes |
|----------|---------|-------|
| Component | `PascalCase.svelte` | In `src/components/` |
| Page | `PascalCase.svelte` | In `src/pages/` |
| Store | `camelCase.svelte.ts` | In `src/stores/` |
| Service | `camelCase.service.ts` | In `src/services/` |
| Utility | `camelCase.ts` | In `src/utils/` |
| Test | `*.test.ts` or `*.spec.ts` | Co-located or in `tests/` |

## Code Quality

- Components: max ~100 lines of template, max ~50 lines of script block
- Functions: max ~30 lines, max 3 nesting levels
- `$effect` must return a cleanup function if it creates subscriptions, timers, or event listeners
- No old Svelte 3/4 reactive syntax (`$:`, `export let`, `createEventDispatcher`, `on:event`)
- `$$props` and `$$restProps` are removed in Svelte 5 — use `$props()` with rest spreading

## Routing (Client-Side)

Standalone Svelte SPAs use client-side routers — not SvelteKit. Recommended options:

- **`svelte-routing`** for simple SPAs
- **`svelte-navigator`** for tree-shaking-friendly routing
- **`@melt-ui/svelte`** for headless component primitives

No `+page.svelte`, `+layout.svelte`, `+page.server.ts` — those are SvelteKit patterns.

## Styling

- Scoped styles in `<style>` blocks (Svelte default — always prefer)
- CSS custom properties for theming: `var(--color-primary)`, `var(--spacing-4)`
- Tailwind CSS utility classes where configured
- Component variants via props, not global CSS class overrides
- Never hardcode hex/rgb color values — use CSS custom properties

## Data Fetching

- Fetch data in service modules (`src/services/`), not directly inside `$effect`
- Use TanStack Query (`@tanstack/svelte-query`) for server state: caching, refetching, optimistic updates
- Raw `fetch` calls only in service modules — components consume service responses
- Wrap async operations: loading state (`$state(true)`), error state (`$state<Error | null>(null)`)

## Error Handling

- Use `{#if error}` blocks for component-level error display
- Wrap async boundaries with try/catch in service functions
- Global unhandled error handling via `window.addEventListener('unhandledrejection', ...)`
- Typed error states: use discriminated union `{ status: 'idle' | 'loading' | 'success' | 'error' }`

## Build (Vite)

- `@sveltejs/vite-plugin-svelte` — the only official Vite integration for standalone Svelte
- Library mode: `svelte-package` for publishing component libraries
- `vite build` for app bundles, `vite build --mode lib` for library packages
- `svelte-check` for Svelte-specific TypeScript and template diagnostics
- Environment variables via `import.meta.env.VITE_*` (public) — never expose secrets in the SPA

## Animation & Motion

Reference `shared/frontend-design-theory.md` for design theory guardrails.

### Library Preference
- **Simple transitions**: Svelte built-in directives — `transition:fade`, `in:fly`, `out:slide`, `transition:scale`
- **Spring physics**: `spring()` from `svelte/motion` — native, zero deps, composable
- **Tweened values**: `tweened()` from `svelte/motion` for smooth numeric transitions
- **List reordering**: `animate:flip` for keyed list animations
- **Complex sequences**: GSAP for timeline choreography and scroll-driven effects
- **CSS-only**: hover effects, loading spinners, skeleton pulses

### Svelte-Specific Patterns
- Custom transitions via `transition:` directive with factory functions
- Check `prefers-reduced-motion` via `$effect` + `window.matchMedia('(prefers-reduced-motion: reduce)')`
- `crossfade()` from `svelte/transition` for shared-element transitions between list items
- Spring and tweened stores are rune-compatible via `$derived` wrapping

### Standards
- Timing: <100ms feedback, 150-200ms micro-interactions, 200-350ms transitions, 300-500ms sequences
- Only animate `transform` and `opacity` (GPU-composited — no `width`, `height`, `top`, `left`)
- REQUIRED: `prefers-reduced-motion` support for all animations
- One orchestrated animation moment per view beats scattered independent effects

## Multi-Viewport Design

### Breakpoints
- Mobile: 375px | Tablet: 768px | Desktop: 1280px | Wide: 1536px+

### Mobile (375px)
- Touch targets >= 44px, single-column reflow, 16px min body text
- Use `<img loading="lazy">` with `srcset` for responsive images

### Tablet (768px)
- Adaptive layout (not just scaled mobile), touch+hover hybrid interaction model

### Desktop (1280px+)
- Hover states, generous whitespace, full navigation

### Cross-Viewport
- Same information hierarchy at all sizes, 8pt grid spacing, responsive images with `srcset`

## Accessibility

- All interactive elements keyboard-accessible (Tab, Enter, Escape, Arrow keys)
- Form inputs require associated `<label>` elements or `aria-label`
- Color contrast: minimum 4.5:1 for normal text, 3:1 for large text (WCAG AA)
- Use semantic HTML: `<nav>`, `<main>`, `<article>`, `<section>`, `<button>`
- Focus management for modals and dynamic content: restore focus on close

## Security

- Never embed secrets in source code — use `import.meta.env.VITE_*` for public-facing config only
- Sanitize all user-supplied content before using `{@html}` (XSS risk)
- Store tokens in memory or `sessionStorage` — never `localStorage` (XSS-readable)
- CSRF is the consuming API's responsibility — SPA has no CSRF protection built-in

## Performance

- Use `{#each items as item (item.id)}` with keyed blocks for stable list identity
- Prefer `$derived` over `$effect` for derived computations (no side effects)
- Lazy-import heavy components: `const Heavy = (await import('./Heavy.svelte')).default`
- Use `<img loading="lazy">` for below-fold images
- `{@html}` sparingly and ONLY with sanitized content

## Testing

### Test Framework
- **Vitest** as the test runner with **Testing Library** (`@testing-library/svelte`) for component tests
- **Playwright** for end-to-end tests where needed
- **MSW** (Mock Service Worker) for mocking API calls at the network level

### Integration Test Patterns
- Use `render()` from Testing Library to mount components with props and verify rendered output
- Test component behavior by interacting with rendered output — not internal state
- Mock service modules via Vitest `vi.mock()` for unit-level component isolation
- Use `userEvent` for realistic DOM interactions (click, type, keyboard)

### What to Test
- Component rendering based on props and reactive state changes
- User interactions: click handlers, form input, keyboard navigation
- Conditional rendering: loading/error/empty states
- Store interactions: components reading from and writing to `.svelte.ts` stores
- Service functions: data transformation, error handling, response parsing

### What NOT to Test
- Svelte renders components correctly (Svelte guarantees this)
- `$state` reactivity triggers re-render (the compiler handles this)
- `$derived` computes correctly from state (Svelte guarantees this)
- Vite builds the bundle (CI/CD handles this)

### Example Test Structure
```
src/components/
  Button.svelte
  Button.test.ts              # co-located component test
src/stores/
  user.svelte.ts
  user.svelte.test.ts         # store behavior test
tests/
  e2e/
    user-flow.spec.ts         # Playwright E2E tests
```

For general Vitest patterns, see `modules/testing/vitest.md`.

## Smart Test Rules

- No duplicate tests — grep existing tests before writing new ones
- Test business behavior, not implementation details
- Do NOT test framework guarantees (e.g., Svelte renders components, rune reactivity)
- Do NOT test Vite bundling or `svelte-check` type resolution
- Each test scenario covers a unique code path
- Fewer meaningful tests > high coverage of trivial code

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated components, changing rune patterns, restructuring store contracts.

## Dos and Don'ts

### Do
- Use `$state()` for reactive state, `$derived()` for computed values
- Use `$effect()` with cleanup return for side effects
- Use callback props (`onclick`, `onSelect`) instead of `createEventDispatcher`
- Use `{#snippet}` and `{@render}` for content projection in new components
- Use `.svelte.ts` files with `$state` for shared cross-component state
- Implement loading, error, and empty states for every async data-fetching component

### Don't
- Don't use `$:` reactive statements — use `$derived()` or `$effect()`
- Don't use `export let` for props — use `$props()`
- Don't use `onMount`/`onDestroy` — use `$effect()` with cleanup
- Don't use `on:click` event syntax — use `onclick` directly (Svelte 5)
- Don't use `createEventDispatcher` — use callback props
- Don't use `$$props` or `$$restProps` — use rest spreading in `$props()`
- Don't use SvelteKit patterns (`+page.svelte`, load functions, form actions) — this is standalone Svelte
- Don't use `writable()`/`readable()` stores for first-party state — use `$state` in `.svelte.ts`
- Don't fetch data directly inside `$effect` — use service modules
