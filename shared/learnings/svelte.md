---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "sv-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.820878Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["build", "svelte"]
    source: "cross-project"
    archived: false
    body_ref: "#sv-preempt-001"
  - id: "sv-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.820878Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["migration", "svelte"]
    source: "cross-project"
    archived: false
    body_ref: "#sv-preempt-002"
  - id: "sv-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.820878Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["state", "svelte"]
    source: "cross-project"
    archived: false
    body_ref: "#sv-preempt-003"
  - id: "sv-preempt-004"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.820878Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["state", "svelte"]
    source: "cross-project"
    archived: false
    body_ref: "#sv-preempt-004"
  - id: "sv-preempt-005"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.820878Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "svelte"]
    source: "cross-project"
    archived: false
    body_ref: "#sv-preempt-005"
  - id: "sv-preempt-006"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.820878Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["rendering", "svelte"]
    source: "cross-project"
    archived: false
    body_ref: "#sv-preempt-006"
  - id: "sv-preempt-007"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.820878Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["migration", "svelte"]
    source: "cross-project"
    archived: false
    body_ref: "#sv-preempt-007"
---
# Cross-Project Learnings: svelte

## PREEMPT items

### SV-PREEMPT-001: SvelteKit patterns used in standalone Svelte cause build errors
<a id="sv-preempt-001"></a>
- **Domain:** build
- **Pattern:** Using `+page.svelte`, `+layout.svelte`, load functions, or `$app/` imports in a standalone Svelte SPA (non-SvelteKit) causes build failures. Standalone Svelte uses client-side routers (svelte-routing, svelte-navigator) and manual data fetching.
- **Confidence:** HIGH
- **Hit count:** 0

### SV-PREEMPT-002: Old event syntax on:click replaced by onclick in Svelte 5
<a id="sv-preempt-002"></a>
- **Domain:** migration
- **Pattern:** Svelte 5 uses standard DOM event attributes (`onclick`, `oninput`) instead of `on:click` directive syntax. Using `on:click` in Svelte 5 produces compilation warnings or errors. Similarly, `createEventDispatcher` is replaced by callback props.
- **Confidence:** HIGH
- **Hit count:** 0

### SV-PREEMPT-003: writable/readable stores replaced by $state in .svelte.ts files
<a id="sv-preempt-003"></a>
- **Domain:** state
- **Pattern:** Svelte 5 rune-based state (`$state` in `.svelte.ts` files) replaces `writable()`, `readable()`, and `derived()` from `svelte/store`. The old store API still works for third-party library compatibility but should not be used for first-party state.
- **Confidence:** HIGH
- **Hit count:** 0

### SV-PREEMPT-004: $effect used for derived computations instead of $derived
<a id="sv-preempt-004"></a>
- **Domain:** state
- **Pattern:** Using `$effect(() => { result = compute(input) })` for values derived from state introduces unnecessary side effects and potential timing issues. Use `$derived(compute(input))` which is synchronous and optimized by the Svelte compiler.
- **Confidence:** HIGH
- **Hit count:** 0

### SV-PREEMPT-005: {@html} without sanitization enables XSS
<a id="sv-preempt-005"></a>
- **Domain:** security
- **Pattern:** `{@html userContent}` renders raw HTML without escaping. User-supplied content injected this way enables cross-site scripting attacks. Always sanitize HTML with a library (DOMPurify) before rendering with `{@html}`, or avoid it entirely.
- **Confidence:** HIGH
- **Hit count:** 0

### SV-PREEMPT-006: Keyed each blocks missing causes incorrect state during list mutations
<a id="sv-preempt-006"></a>
- **Domain:** rendering
- **Pattern:** `{#each items as item}` without a key `(item.id)` reuses DOM elements by index. When items are reordered, inserted, or deleted, component state (input values, expanded flags) attaches to the wrong item. Always use `{#each items as item (item.id)}`.
- **Confidence:** HIGH
- **Hit count:** 0

### SV-PREEMPT-007: $$props and $$restProps removed in Svelte 5
<a id="sv-preempt-007"></a>
- **Domain:** migration
- **Pattern:** `$$props` and `$$restProps` are no longer available in Svelte 5. Use `$props()` with rest spreading: `let { class: className, ...rest } = $props()`. Components relying on `$$props` will fail to compile after upgrading.
- **Confidence:** HIGH
- **Hit count:** 0
