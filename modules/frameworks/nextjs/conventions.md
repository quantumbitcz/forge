# Next.js Framework Conventions

> Framework-specific conventions for Next.js projects. Language idioms are in `modules/languages/typescript.md`. Generic testing patterns are in `modules/testing/vitest.md`.

## Architecture (App Router)

| Layer | Responsibility | Location |
|-------|---------------|----------|
| Page | Route-level Server Component, data fetching | `app/{route}/page.tsx` |
| Layout | Shared UI wrapping child routes | `app/{route}/layout.tsx` |
| Route Handler | REST API endpoints (replaces API routes) | `app/api/{resource}/route.ts` |
| Server Component | Data fetching, async rendering, no interactivity | `app/` (default) |
| Client Component | Interactivity, browser APIs, event handlers | Must declare `"use client"` |
| Middleware | Auth, redirects, header rewriting | `middleware.ts` at project root |

**Dependency rule:** Server Components never import Client Components that use browser APIs without wrapping in `Suspense`. Client Components never perform direct DB/filesystem access — that belongs in Server Components or Route Handlers.

## App Router Patterns

- Use App Router (`app/`) by default — Pages Router (`pages/`) is legacy
- Colocate components, hooks, and utilities near the route that uses them
- Route segments are folders; `page.tsx` makes a segment publicly accessible
- `layout.tsx` wraps all children and persists across navigations (no remount)
- `template.tsx` creates a new instance on every navigation (for animations, per-page effects)
- `loading.tsx` defines Suspense boundaries per route segment automatically
- `error.tsx` defines React Error Boundaries per segment — must be a Client Component
- `not-found.tsx` renders on `notFound()` throws or unmatched routes

## Server vs Client Components

### Server Components (default)
- No `useState`, `useEffect`, or browser APIs
- Can `async`/`await` directly — no useEffect for data loading
- Access databases, file system, and server-side secrets directly
- Pass serializable props to Client Components only
- Wrap in `<Suspense>` to stream partial UI while data loads

### Client Components
- Declare `"use client"` at the top of the file — it is a boundary, not a per-component directive
- Use for: event handlers, browser APIs, `useState`, `useEffect`, third-party state libraries
- Keep Client Components as leaf nodes — push `"use client"` as deep as possible
- Never import Server Components into Client Components

## Rendering Strategies

Configure per route segment via exported constants:

```ts
export const dynamic = 'force-dynamic'   // SSR (no caching)
export const dynamic = 'force-static'    // Full static export
export const revalidate = 60             // ISR: revalidate every 60s
export const revalidate = false          // Permanently cached (default for static)
```

- Default: static where possible, dynamic when `cookies()`, `headers()`, or dynamic APIs are used
- Streaming: wrap slow Server Components in `<Suspense fallback={<Skeleton />}>` for progressive rendering
- Partial Prerendering (PPR): mix static shell with dynamic holes using `<Suspense>` boundaries

## Data Fetching

- `fetch()` in Server Components is extended with caching: `fetch(url, { next: { revalidate: 60 } })`
- Use `React.cache()` to deduplicate identical requests within a render pass
- Server Actions for mutations: `"use server"` directive, called from Client Components or forms
- Never use `getServerSideProps`/`getStaticProps` — these are Pages Router only
- Parallel data fetching with `Promise.all()` to avoid waterfall

```ts
// Deduplication across multiple components in one render
import { cache } from 'react'
export const getUser = cache(async (id: string) => {
  return db.user.findUnique({ where: { id } })
})
```

## Navigation

- `<Link href="...">` for client-side navigation — never use `<a>` for internal links
- `useRouter()` for programmatic navigation in Client Components
- `redirect(url)` in Server Components and Route Handlers (throws, so no return needed)
- `permanentRedirect(url)` for 308 permanent redirects
- Parallel routes (`@slot/`) for rendering multiple pages in the same layout simultaneously
- Intercepting routes (`(.)`, `(..)`, `(...)`) for modal-style UX without full page change

## Route Handlers

```ts
// app/api/users/route.ts
export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url)
  // ...
  return NextResponse.json({ users }, { status: 200 })
}

export async function POST(request: NextRequest) {
  const body = await request.json()
  // validate input before use
  return NextResponse.json({ user }, { status: 201 })
}
```

- Validate all input before processing — never trust `request.json()` directly
- Use `NextRequest`/`NextResponse` for full Next.js feature access
- Route Handlers run on the Edge or Node.js runtime (configure via `export const runtime = 'edge'`)

## Server Actions

```ts
// actions/user.ts
'use server'

import { z } from 'zod'
import { revalidatePath } from 'next/cache'

const schema = z.object({ name: z.string().min(1) })

export async function updateUser(formData: FormData) {
  const parsed = schema.safeParse(Object.fromEntries(formData))
  if (!parsed.success) return { error: parsed.error.flatten() }
  // mutate ...
  revalidatePath('/users')
}
```

- Always validate with Zod or equivalent before mutating
- Return typed result objects — throw only for unrecoverable errors
- Call `revalidatePath()` or `revalidateTag()` to invalidate cached data after mutations

## Metadata

```ts
// Static metadata
export const metadata: Metadata = {
  title: 'Page Title',
  description: 'Page description',
  openGraph: { ... }
}

// Dynamic metadata
export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const product = await getProduct(params.id)
  return { title: product.name }
}
```

- Use `export const metadata` or `generateMetadata()` — never `<Head>` from `next/head`
- Define metadata at every route segment for SEO
- Use `metadataBase` in root layout to resolve relative Open Graph image URLs

## Styling

- CSS Modules (`.module.css`) for component-scoped styles — no class name collisions
- Tailwind CSS for utility classes when configured — use design tokens
- `next/font` for font optimization — fonts loaded at build time, no layout shift
- No inline `style` objects unless truly dynamic (data-driven values)

## Images and Assets

- Always use `<Image>` from `next/image` — automatic WebP conversion, lazy loading, layout shift prevention
- Specify `width` and `height` for fixed images; use `fill` + sized container for responsive
- External image domains must be listed in `next.config.ts` `remotePatterns`
- Never use `<img>` for content images

## Security

- Server Actions include built-in CSRF protection via Origin header validation
- All `"use server"` functions are public endpoints — validate input and check authorization
- Environment variables: server-side secrets must NOT use `NEXT_PUBLIC_` prefix
- `NEXT_PUBLIC_` variables are inlined at build time and visible to all clients
- Validate and sanitize all user-supplied content before rendering
- Use `headers()` from `next/headers` for request-time header access — never pass via props

## Performance

- Dynamic imports: `const Chart = dynamic(() => import('./Chart'), { ssr: false })` for client-only heavy components
- `React.lazy()` works within Client Components for code splitting
- Bundle analysis: `@next/bundle-analyzer` to identify large dependencies
- Image priority: set `priority` on above-the-fold images to preload
- Route prefetching: `<Link prefetch>` fetches on hover (default in production)

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Smart Test Rules

- No duplicate tests — grep existing tests before generating
- Test behavior, not implementation
- Skip framework guarantees (don't test Next.js routing itself)
- One assertion focus per `it()` — multiple asserts OK if same behavior

## Dos and Don'ts

### Do
- Default to Server Components — add `"use client"` only when interactivity is required
- Use `loading.tsx` and `error.tsx` at every route segment that fetches data
- Validate Server Action inputs with Zod before any mutation
- Use `next/image` for all content images
- Use `next/font` for all custom fonts
- Use `<Link>` for all internal navigation
- Colocate route-specific components with their route segment
- Use `React.cache()` to deduplicate data fetching across multiple Server Components
- Configure `revalidate` per route segment to match data freshness requirements

### Don't
- Don't use Pages Router (`pages/`) for new development — use App Router (`app/`)
- Don't use `getServerSideProps` or `getStaticProps` — these don't exist in App Router
- Don't import `next/head` — use the Metadata API instead
- Don't use `_app.tsx` or `_document.tsx` — use `layout.tsx` and `template.tsx`
- Don't fetch data in Client Components with `useEffect` when a Server Component can do it
- Don't store server-only secrets in `NEXT_PUBLIC_` variables
- Don't put `"use client"` on root layouts — it forces the entire tree into client rendering
- Don't use `<img>` for content images — use `next/image`
- Don't mutate without calling `revalidatePath()` or `revalidateTag()` after Server Actions
- Don't ignore TypeScript errors — `strict: true` required in tsconfig
