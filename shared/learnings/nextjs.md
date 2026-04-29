---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "nx-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780445Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["rendering", "nextjs"]
    source: "cross-project"
    archived: false
    body_ref: "nx-preempt-001"
  - id: "nx-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780445Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["data-fetching", "nextjs"]
    source: "cross-project"
    archived: false
    body_ref: "nx-preempt-002"
  - id: "nx-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780445Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "nextjs"]
    source: "cross-project"
    archived: false
    body_ref: "nx-preempt-003"
  - id: "nx-preempt-004"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780445Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "nextjs"]
    source: "cross-project"
    archived: false
    body_ref: "nx-preempt-004"
  - id: "nx-preempt-005"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780445Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["caching", "nextjs"]
    source: "cross-project"
    archived: false
    body_ref: "nx-preempt-005"
  - id: "nx-preempt-006"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780445Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["rendering", "nextjs"]
    source: "cross-project"
    archived: false
    body_ref: "nx-preempt-006"
  - id: "nx-preempt-007"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780445Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["routing", "nextjs"]
    source: "cross-project"
    archived: false
    body_ref: "nx-preempt-007"
  - id: "nx-preempt-008"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780445Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["rendering", "nextjs"]
    source: "cross-project"
    archived: false
    body_ref: "nx-preempt-008"
  - id: "common-pitfalls"
    base_confidence: 0.75
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780445Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["nextjs"]
    source: "cross-project"
    archived: false
    body_ref: "common-pitfalls"
  - id: "effective-patterns"
    base_confidence: 0.75
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780445Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["nextjs"]
    source: "cross-project"
    archived: false
    body_ref: "effective-patterns"
---
# Cross-Project Learnings: nextjs

## PREEMPT items

### NX-PREEMPT-001: Server Component importing Client Component with browser APIs crashes SSR
<a id="nx-preempt-001"></a>
- **Domain:** rendering
- **Pattern:** Server Components cannot import modules that use `window`, `document`, or browser APIs at module scope. The import itself runs on the server and throws. Wrap browser-dependent components in `"use client"` files and import those from Server Components.
- **Confidence:** HIGH
- **Hit count:** 0

### NX-PREEMPT-002: useEffect for data fetching in App Router defeats server-side rendering
<a id="nx-preempt-002"></a>
- **Domain:** data-fetching
- **Pattern:** Fetching data in `useEffect` inside Client Components produces an empty shell on the server and a loading flash on the client. Move data fetching to Server Components (async/await directly) and pass data as props to Client Components.
- **Confidence:** HIGH
- **Hit count:** 0

### NX-PREEMPT-003: NEXT_PUBLIC_ prefix exposes secrets to the client bundle
<a id="nx-preempt-003"></a>
- **Domain:** security
- **Pattern:** Environment variables prefixed with `NEXT_PUBLIC_` are inlined at build time and visible in the client JavaScript bundle. Database URLs, API secrets, and auth tokens must NOT use this prefix. Only use `NEXT_PUBLIC_` for values safe for public consumption.
- **Confidence:** HIGH
- **Hit count:** 0

### NX-PREEMPT-004: Server Actions are public endpoints — must validate input and auth
<a id="nx-preempt-004"></a>
- **Domain:** security
- **Pattern:** Functions marked `"use server"` are exposed as POST endpoints callable by anyone. They must validate input (Zod schema) and check authorization, just like API routes. Treat every Server Action as an unauthenticated endpoint by default.
- **Confidence:** HIGH
- **Hit count:** 0

### NX-PREEMPT-005: Missing revalidatePath after Server Action mutation shows stale data
<a id="nx-preempt-005"></a>
- **Domain:** caching
- **Pattern:** Next.js aggressively caches page data. After a mutation in a Server Action, calling `revalidatePath()` or `revalidateTag()` is required to invalidate the cache. Without it, the page continues showing pre-mutation data even after the mutation succeeds.
- **Confidence:** HIGH
- **Hit count:** 0

### NX-PREEMPT-006: "use client" on layout forces entire subtree to client rendering
<a id="nx-preempt-006"></a>
- **Domain:** rendering
- **Pattern:** Adding `"use client"` to a root or high-level `layout.tsx` forces all child pages and components to render as Client Components, losing SSR benefits for the entire subtree. Keep layouts as Server Components; push `"use client"` to the smallest leaf components that need interactivity.
- **Confidence:** HIGH
- **Hit count:** 0

### NX-PREEMPT-007: Pages Router APIs mixed with App Router cause routing conflicts
<a id="nx-preempt-007"></a>
- **Domain:** routing
- **Pattern:** Having both `pages/api/users.ts` (Pages Router) and `app/api/users/route.ts` (App Router) for the same path causes unpredictable routing. Use App Router Route Handlers exclusively for new code. Never mix `getServerSideProps` with Server Components.
- **Confidence:** HIGH
- **Hit count:** 0

### NX-PREEMPT-008: Dynamic imports with ssr:false break when component uses server data
<a id="nx-preempt-008"></a>
- **Domain:** rendering
- **Pattern:** `dynamic(() => import('./Chart'), { ssr: false })` renders nothing on the server. If the component's parent is a Server Component that passes server-fetched data, the data is available but the component is not rendered until client hydration. Use `<Suspense>` fallback to avoid layout shift.
- **Confidence:** MEDIUM
- **Hit count:** 0

## App Router Variant Learnings

### Common Pitfalls
<a id="common-pitfalls"></a>
<!-- Populated by retrospective agent: server/client boundary issues, caching gotchas -->

### Effective Patterns
<a id="effective-patterns"></a>
<!-- Populated by retrospective agent -->
