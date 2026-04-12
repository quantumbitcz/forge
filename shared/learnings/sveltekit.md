# Cross-Project Learnings: sveltekit

## PREEMPT items

### SK-PREEMPT-001: Secrets in +page.ts are exposed to the client
- **Domain:** security
- **Pattern:** `+page.ts` (universal load) runs on both server and client. Any secret (API key, database URL) used in `+page.ts` is bundled into the client JavaScript. Move secrets to `+page.server.ts` which runs server-side only.
- **Confidence:** HIGH
- **Hit count:** 0

### SK-PREEMPT-002: Old Svelte 3/4 reactive syntax ($:, export let) breaks in Svelte 5
- **Domain:** migration
- **Pattern:** Svelte 5 runes (`$state`, `$derived`, `$props`) replace `$:` reactive statements, `export let` props, and `createEventDispatcher`. Using old syntax in a Svelte 5 project causes compilation errors or silent behavioral differences. Audit and migrate all components.
- **Confidence:** HIGH
- **Hit count:** 0

### SK-PREEMPT-003: goto() for data refresh causes full page navigation instead of invalidation
- **Domain:** data-fetching
- **Pattern:** Using `goto('/current-page')` to refresh data after a mutation causes a full navigation cycle (flicker, scroll reset). Use `invalidateAll()` or `invalidate('app:tag')` to re-run load functions without navigation.
- **Confidence:** HIGH
- **Hit count:** 0

### SK-PREEMPT-004: Form actions without use:enhance cause full page reload
- **Domain:** forms
- **Pattern:** `<form method="POST">` without `use:enhance` submits the form as a traditional browser POST, causing a full page reload. Add `use:enhance` for progressive enhancement that preserves SPA behavior while keeping forms functional without JavaScript.
- **Confidence:** HIGH
- **Hit count:** 0

### SK-PREEMPT-005: $effect without cleanup leaks subscriptions and timers
- **Domain:** state
- **Pattern:** `$effect(() => { ... })` that creates event listeners, timers, or subscriptions without returning a cleanup function leaks resources across navigations. Always return a cleanup function: `$effect(() => { const id = setInterval(...); return () => clearInterval(id) })`.
- **Confidence:** HIGH
- **Hit count:** 0

### SK-PREEMPT-006: Missing +error.svelte causes unhandled errors to show default error page
- **Domain:** error-handling
- **Pattern:** Without `+error.svelte` at the appropriate route level, errors thrown in load functions display SvelteKit's default error page with no styling or branding. Add `+error.svelte` boundaries at every route segment that fetches data.
- **Confidence:** MEDIUM
- **Hit count:** 0

### SK-PREEMPT-007: Component imports from src/routes break library encapsulation
- **Domain:** architecture
- **Pattern:** Components in `src/lib/` importing from `src/routes/` creates circular dependencies and breaks component reusability. The dependency must flow one direction: pages import from lib, never the reverse.
- **Confidence:** HIGH
- **Hit count:** 0
