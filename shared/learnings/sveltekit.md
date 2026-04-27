---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "sk-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.821352Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "sveltekit"]
    source: "cross-project"
    archived: false
    body_ref: "#sk-preempt-001"
  - id: "sk-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.821352Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["migration", "sveltekit"]
    source: "cross-project"
    archived: false
    body_ref: "#sk-preempt-002"
  - id: "sk-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.821352Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["data-fetching", "sveltekit"]
    source: "cross-project"
    archived: false
    body_ref: "#sk-preempt-003"
  - id: "sk-preempt-004"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.821352Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["forms", "sveltekit"]
    source: "cross-project"
    archived: false
    body_ref: "#sk-preempt-004"
  - id: "sk-preempt-005"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.821352Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["state", "sveltekit"]
    source: "cross-project"
    archived: false
    body_ref: "#sk-preempt-005"
  - id: "sk-preempt-006"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.821352Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["error-handling", "sveltekit"]
    source: "cross-project"
    archived: false
    body_ref: "#sk-preempt-006"
  - id: "sk-preempt-007"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.821352Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["architecture", "sveltekit"]
    source: "cross-project"
    archived: false
    body_ref: "#sk-preempt-007"
---
# Cross-Project Learnings: sveltekit

## PREEMPT items

### SK-PREEMPT-001: Secrets in +page.ts are exposed to the client
<a id="sk-preempt-001"></a>
- **Domain:** security
- **Pattern:** `+page.ts` (universal load) runs on both server and client. Any secret (API key, database URL) used in `+page.ts` is bundled into the client JavaScript. Move secrets to `+page.server.ts` which runs server-side only.
- **Confidence:** HIGH
- **Hit count:** 0

### SK-PREEMPT-002: Old Svelte 3/4 reactive syntax ($:, export let) breaks in Svelte 5
<a id="sk-preempt-002"></a>
- **Domain:** migration
- **Pattern:** Svelte 5 runes (`$state`, `$derived`, `$props`) replace `$:` reactive statements, `export let` props, and `createEventDispatcher`. Using old syntax in a Svelte 5 project causes compilation errors or silent behavioral differences. Audit and migrate all components.
- **Confidence:** HIGH
- **Hit count:** 0

### SK-PREEMPT-003: goto() for data refresh causes full page navigation instead of invalidation
<a id="sk-preempt-003"></a>
- **Domain:** data-fetching
- **Pattern:** Using `goto('/current-page')` to refresh data after a mutation causes a full navigation cycle (flicker, scroll reset). Use `invalidateAll()` or `invalidate('app:tag')` to re-run load functions without navigation.
- **Confidence:** HIGH
- **Hit count:** 0

### SK-PREEMPT-004: Form actions without use:enhance cause full page reload
<a id="sk-preempt-004"></a>
- **Domain:** forms
- **Pattern:** `<form method="POST">` without `use:enhance` submits the form as a traditional browser POST, causing a full page reload. Add `use:enhance` for progressive enhancement that preserves SPA behavior while keeping forms functional without JavaScript.
- **Confidence:** HIGH
- **Hit count:** 0

### SK-PREEMPT-005: $effect without cleanup leaks subscriptions and timers
<a id="sk-preempt-005"></a>
- **Domain:** state
- **Pattern:** `$effect(() => { ... })` that creates event listeners, timers, or subscriptions without returning a cleanup function leaks resources across navigations. Always return a cleanup function: `$effect(() => { const id = setInterval(...); return () => clearInterval(id) })`.
- **Confidence:** HIGH
- **Hit count:** 0

### SK-PREEMPT-006: Missing +error.svelte causes unhandled errors to show default error page
<a id="sk-preempt-006"></a>
- **Domain:** error-handling
- **Pattern:** Without `+error.svelte` at the appropriate route level, errors thrown in load functions display SvelteKit's default error page with no styling or branding. Add `+error.svelte` boundaries at every route segment that fetches data.
- **Confidence:** MEDIUM
- **Hit count:** 0

### SK-PREEMPT-007: Component imports from src/routes break library encapsulation
<a id="sk-preempt-007"></a>
- **Domain:** architecture
- **Pattern:** Components in `src/lib/` importing from `src/routes/` creates circular dependencies and breaks component reusability. The dependency must flow one direction: pages import from lib, never the reverse.
- **Confidence:** HIGH
- **Hit count:** 0
