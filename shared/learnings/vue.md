---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "vu-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.829532Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["data-fetching", "vue"]
    source: "cross-project"
    archived: false
    body_ref: "vu-preempt-001"
  - id: "vu-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.829532Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["state", "vue"]
    source: "cross-project"
    archived: false
    body_ref: "vu-preempt-002"
  - id: "vu-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.829532Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["architecture", "vue"]
    source: "cross-project"
    archived: false
    body_ref: "vu-preempt-003"
  - id: "vu-preempt-004"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.829532Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "vue"]
    source: "cross-project"
    archived: false
    body_ref: "vu-preempt-004"
  - id: "vu-preempt-005"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.829532Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "vue"]
    source: "cross-project"
    archived: false
    body_ref: "vu-preempt-005"
  - id: "vu-preempt-006"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.829532Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["rendering", "vue"]
    source: "cross-project"
    archived: false
    body_ref: "vu-preempt-006"
  - id: "vu-preempt-007"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.829532Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["data-fetching", "vue"]
    source: "cross-project"
    archived: false
    body_ref: "vu-preempt-007"
  - id: "vu-preempt-008"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.829532Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["architecture", "vue"]
    source: "cross-project"
    archived: false
    body_ref: "vu-preempt-008"
  - id: "common-pitfalls"
    base_confidence: 0.75
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.829532Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["vue"]
    source: "cross-project"
    archived: false
    body_ref: "common-pitfalls"
  - id: "effective-patterns"
    base_confidence: 0.75
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.829532Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["vue"]
    source: "cross-project"
    archived: false
    body_ref: "effective-patterns"
---
# Cross-Project Learnings: vue

## PREEMPT items

### VU-PREEMPT-001: useFetch called inside event handlers causes SSR hydration mismatch
<a id="vu-preempt-001"></a>
- **Domain:** data-fetching
- **Pattern:** `useFetch` and `useAsyncData` must be called in `<script setup>` scope (setup context), not inside event handlers or callbacks. Calling them in `onclick` handlers produces hydration mismatches and unpredictable behavior. Use `$fetch` for user-triggered requests.
- **Confidence:** HIGH
- **Hit count:** 0

### VU-PREEMPT-002: Destructuring Pinia store state loses reactivity
<a id="vu-preempt-002"></a>
- **Domain:** state
- **Pattern:** `const { count, items } = useMyStore()` destructures reactive properties into plain values, losing reactivity. Use `storeToRefs()`: `const { count, items } = storeToRefs(useMyStore())`. Actions (methods) can be destructured directly without `storeToRefs`.
- **Confidence:** HIGH
- **Hit count:** 0

### VU-PREEMPT-003: Options API mixed with Composition API creates inconsistent codebase
<a id="vu-preempt-003"></a>
- **Domain:** architecture
- **Pattern:** Mixing `data()`, `methods:`, `computed:` (Options API) with `<script setup>` (Composition API) in the same project creates cognitive overhead and inconsistent patterns. Use `<script setup lang="ts">` exclusively for all components.
- **Confidence:** HIGH
- **Hit count:** 0

### VU-PREEMPT-004: v-html with untrusted content enables XSS attacks
<a id="vu-preempt-004"></a>
- **Domain:** security
- **Pattern:** `v-html` renders raw HTML without sanitization. User-generated content injected via `v-html` enables cross-site scripting. Always sanitize content with DOMPurify before using `v-html`, or use `{{ }}` interpolation which auto-escapes.
- **Confidence:** HIGH
- **Hit count:** 0

### VU-PREEMPT-005: Server secrets in runtimeConfig.public are exposed to the client
<a id="vu-preempt-005"></a>
- **Domain:** security
- **Pattern:** Values in `runtimeConfig.public` are serialized into the client bundle and visible in browser DevTools. Database passwords, API keys, and tokens must go in `runtimeConfig` (server-only), accessed via `useRuntimeConfig()` only in server routes and server middleware.
- **Confidence:** HIGH
- **Hit count:** 0

### VU-PREEMPT-006: Array index as :key in v-for causes state bugs on mutation
<a id="vu-preempt-006"></a>
- **Domain:** rendering
- **Pattern:** Using `:key="index"` in `v-for` over mutable lists causes Vue to reuse component instances incorrectly when items are inserted, deleted, or reordered. Use a stable unique ID (`:key="item.id"`) to ensure correct DOM element tracking.
- **Confidence:** HIGH
- **Hit count:** 0

### VU-PREEMPT-007: Missing key on useFetch causes duplicate requests across navigations
<a id="vu-preempt-007"></a>
- **Domain:** data-fetching
- **Pattern:** `useFetch('/api/data')` without a `key` option uses the URL as the cache key. When the same URL is fetched in different components or pages, Nuxt may deduplicate or cache incorrectly. Provide explicit `key` values for all `useFetch` calls to control caching behavior.
- **Confidence:** MEDIUM
- **Hit count:** 0

### VU-PREEMPT-008: Nuxt auto-imports hide dependency sources
<a id="vu-preempt-008"></a>
- **Domain:** architecture
- **Pattern:** Nuxt auto-imports `ref`, `computed`, `useFetch`, `useRoute`, etc., making it unclear where APIs come from when reading code. While convenient, this causes confusion for new team members and IDE issues. Document which auto-imports are used in the project CLAUDE.md.
- **Confidence:** MEDIUM
- **Hit count:** 0

## TypeScript Variant Learnings

### Common Pitfalls
<a id="common-pitfalls"></a>
<!-- Populated by retrospective agent: Volar quirks, defineProps type inference -->

### Effective Patterns
<a id="effective-patterns"></a>
<!-- Populated by retrospective agent -->
