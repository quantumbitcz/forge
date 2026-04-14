# Cross-Project Learnings: vue

## PREEMPT items

### VU-PREEMPT-001: useFetch called inside event handlers causes SSR hydration mismatch
- **Domain:** data-fetching
- **Pattern:** `useFetch` and `useAsyncData` must be called in `<script setup>` scope (setup context), not inside event handlers or callbacks. Calling them in `onclick` handlers produces hydration mismatches and unpredictable behavior. Use `$fetch` for user-triggered requests.
- **Confidence:** HIGH
- **Hit count:** 0

### VU-PREEMPT-002: Destructuring Pinia store state loses reactivity
- **Domain:** state
- **Pattern:** `const { count, items } = useMyStore()` destructures reactive properties into plain values, losing reactivity. Use `storeToRefs()`: `const { count, items } = storeToRefs(useMyStore())`. Actions (methods) can be destructured directly without `storeToRefs`.
- **Confidence:** HIGH
- **Hit count:** 0

### VU-PREEMPT-003: Options API mixed with Composition API creates inconsistent codebase
- **Domain:** architecture
- **Pattern:** Mixing `data()`, `methods:`, `computed:` (Options API) with `<script setup>` (Composition API) in the same project creates cognitive overhead and inconsistent patterns. Use `<script setup lang="ts">` exclusively for all components.
- **Confidence:** HIGH
- **Hit count:** 0

### VU-PREEMPT-004: v-html with untrusted content enables XSS attacks
- **Domain:** security
- **Pattern:** `v-html` renders raw HTML without sanitization. User-generated content injected via `v-html` enables cross-site scripting. Always sanitize content with DOMPurify before using `v-html`, or use `{{ }}` interpolation which auto-escapes.
- **Confidence:** HIGH
- **Hit count:** 0

### VU-PREEMPT-005: Server secrets in runtimeConfig.public are exposed to the client
- **Domain:** security
- **Pattern:** Values in `runtimeConfig.public` are serialized into the client bundle and visible in browser DevTools. Database passwords, API keys, and tokens must go in `runtimeConfig` (server-only), accessed via `useRuntimeConfig()` only in server routes and server middleware.
- **Confidence:** HIGH
- **Hit count:** 0

### VU-PREEMPT-006: Array index as :key in v-for causes state bugs on mutation
- **Domain:** rendering
- **Pattern:** Using `:key="index"` in `v-for` over mutable lists causes Vue to reuse component instances incorrectly when items are inserted, deleted, or reordered. Use a stable unique ID (`:key="item.id"`) to ensure correct DOM element tracking.
- **Confidence:** HIGH
- **Hit count:** 0

### VU-PREEMPT-007: Missing key on useFetch causes duplicate requests across navigations
- **Domain:** data-fetching
- **Pattern:** `useFetch('/api/data')` without a `key` option uses the URL as the cache key. When the same URL is fetched in different components or pages, Nuxt may deduplicate or cache incorrectly. Provide explicit `key` values for all `useFetch` calls to control caching behavior.
- **Confidence:** MEDIUM
- **Hit count:** 0

### VU-PREEMPT-008: Nuxt auto-imports hide dependency sources
- **Domain:** architecture
- **Pattern:** Nuxt auto-imports `ref`, `computed`, `useFetch`, `useRoute`, etc., making it unclear where APIs come from when reading code. While convenient, this causes confusion for new team members and IDE issues. Document which auto-imports are used in the project CLAUDE.md.
- **Confidence:** MEDIUM
- **Hit count:** 0

## TypeScript Variant Learnings

### Common Pitfalls
<!-- Populated by retrospective agent: Volar quirks, defineProps type inference -->

### Effective Patterns
<!-- Populated by retrospective agent -->
