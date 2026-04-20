---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
# Cross-Project Learnings: nextjs

## PREEMPT items

### NX-PREEMPT-001: Server Component importing Client Component with browser APIs crashes SSR
- **Domain:** rendering
- **Pattern:** Server Components cannot import modules that use `window`, `document`, or browser APIs at module scope. The import itself runs on the server and throws. Wrap browser-dependent components in `"use client"` files and import those from Server Components.
- **Confidence:** HIGH
- **Hit count:** 0

### NX-PREEMPT-002: useEffect for data fetching in App Router defeats server-side rendering
- **Domain:** data-fetching
- **Pattern:** Fetching data in `useEffect` inside Client Components produces an empty shell on the server and a loading flash on the client. Move data fetching to Server Components (async/await directly) and pass data as props to Client Components.
- **Confidence:** HIGH
- **Hit count:** 0

### NX-PREEMPT-003: NEXT_PUBLIC_ prefix exposes secrets to the client bundle
- **Domain:** security
- **Pattern:** Environment variables prefixed with `NEXT_PUBLIC_` are inlined at build time and visible in the client JavaScript bundle. Database URLs, API secrets, and auth tokens must NOT use this prefix. Only use `NEXT_PUBLIC_` for values safe for public consumption.
- **Confidence:** HIGH
- **Hit count:** 0

### NX-PREEMPT-004: Server Actions are public endpoints — must validate input and auth
- **Domain:** security
- **Pattern:** Functions marked `"use server"` are exposed as POST endpoints callable by anyone. They must validate input (Zod schema) and check authorization, just like API routes. Treat every Server Action as an unauthenticated endpoint by default.
- **Confidence:** HIGH
- **Hit count:** 0

### NX-PREEMPT-005: Missing revalidatePath after Server Action mutation shows stale data
- **Domain:** caching
- **Pattern:** Next.js aggressively caches page data. After a mutation in a Server Action, calling `revalidatePath()` or `revalidateTag()` is required to invalidate the cache. Without it, the page continues showing pre-mutation data even after the mutation succeeds.
- **Confidence:** HIGH
- **Hit count:** 0

### NX-PREEMPT-006: "use client" on layout forces entire subtree to client rendering
- **Domain:** rendering
- **Pattern:** Adding `"use client"` to a root or high-level `layout.tsx` forces all child pages and components to render as Client Components, losing SSR benefits for the entire subtree. Keep layouts as Server Components; push `"use client"` to the smallest leaf components that need interactivity.
- **Confidence:** HIGH
- **Hit count:** 0

### NX-PREEMPT-007: Pages Router APIs mixed with App Router cause routing conflicts
- **Domain:** routing
- **Pattern:** Having both `pages/api/users.ts` (Pages Router) and `app/api/users/route.ts` (App Router) for the same path causes unpredictable routing. Use App Router Route Handlers exclusively for new code. Never mix `getServerSideProps` with Server Components.
- **Confidence:** HIGH
- **Hit count:** 0

### NX-PREEMPT-008: Dynamic imports with ssr:false break when component uses server data
- **Domain:** rendering
- **Pattern:** `dynamic(() => import('./Chart'), { ssr: false })` renders nothing on the server. If the component's parent is a Server Component that passes server-fetched data, the data is available but the component is not rendered until client hydration. Use `<Suspense>` fallback to avoid layout shift.
- **Confidence:** MEDIUM
- **Hit count:** 0

## App Router Variant Learnings

### Common Pitfalls
<!-- Populated by retrospective agent: server/client boundary issues, caching gotchas -->

### Effective Patterns
<!-- Populated by retrospective agent -->
