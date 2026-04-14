# Next.js -- App Router Variant

> App Router architecture patterns for Next.js 13.4+ projects. Extends `modules/languages/typescript.md` and `modules/frameworks/nextjs/conventions.md`. Applies when `variant: app-router` is set in `forge.local.md`.

## Architecture

### File Conventions

App Router uses file-system routing under `app/`:

| File | Purpose |
|---|---|
| `page.tsx` | Route UI (required for route to be accessible) |
| `layout.tsx` | Shared UI wrapping child segments |
| `loading.tsx` | Suspense fallback for the segment |
| `error.tsx` | Error boundary for the segment |
| `not-found.tsx` | 404 UI for the segment |
| `route.ts` | API endpoint (no UI) |
| `template.tsx` | Re-rendered layout (no state preservation) |
| `default.tsx` | Parallel route fallback |

### Server vs Client Components

- **Default is Server Component** -- no directive needed
- Add `"use client"` only at the leaf component that needs interactivity
- Server Components can `await` data directly -- no `useEffect` or `useState` for fetching
- Client Components cannot use `async/await` at the component level

```tsx
// Server Component (default)
export default async function UsersPage() {
  const users = await db.users.findMany()
  return <UserList users={users} />
}

// Client Component (needs interactivity)
'use client'
export function SearchFilter({ onSearch }: { onSearch: (q: string) => void }) {
  const [query, setQuery] = useState('')
  // ...
}
```

## Data Fetching

- Fetch data in Server Components with `async/await` -- no `getServerSideProps` or `getStaticProps`
- Use `fetch()` with `next.revalidate` or `next.tags` for cache control
- Deduplicate identical `fetch()` calls automatically (React cache)

```tsx
async function getUser(id: string) {
  const res = await fetch(`https://api.example.com/users/${id}`, {
    next: { revalidate: 3600, tags: ['user', `user-${id}`] },
  })
  if (!res.ok) throw new Error('Failed to fetch user')
  return res.json() as Promise<User>
}
```

## Server Actions

- Define with `"use server"` directive -- either at function level or file level
- Use for mutations (create, update, delete) -- not for reads
- Always validate input with Zod and check authorization
- Call `revalidatePath()` or `revalidateTag()` after mutations

```tsx
'use server'

import { revalidateTag } from 'next/cache'
import { z } from 'zod'

const CreatePostSchema = z.object({
  title: z.string().min(1).max(200),
  content: z.string().min(1),
})

export async function createPost(formData: FormData) {
  const parsed = CreatePostSchema.safeParse(Object.fromEntries(formData))
  if (!parsed.success) return { error: parsed.error.flatten() }

  await db.posts.create({ data: parsed.data })
  revalidateTag('posts')
}
```

## Route Handlers

- Place in `app/api/` using `route.ts` files
- Export named functions: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`
- Use `NextRequest` and `NextResponse` types

```ts
import { NextRequest, NextResponse } from 'next/server'

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams
  const query = searchParams.get('q')
  // ...
  return NextResponse.json({ results })
}
```

## Metadata

- Export `metadata` object or `generateMetadata()` function from `page.tsx` or `layout.tsx`
- Use `Metadata` type from `next` for static metadata
- Use `generateMetadata` for dynamic metadata based on route params

```tsx
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: { template: '%s | My App', default: 'My App' },
  description: 'App description',
}
```

## Dos

- Colocate related files in route segments (`page.tsx`, `loading.tsx`, `error.tsx` together)
- Use parallel routes (`@modal`, `@sidebar`) for complex layouts
- Use route groups `(marketing)`, `(dashboard)` to organize without affecting URL
- Wrap async boundaries with `<Suspense>` and provide meaningful fallbacks
- Use `next/image` for all images -- never raw `<img>` tags
- Use `next/link` for all internal navigation
- Use `next/font` for font loading

## Don'ts

- Don't use Pages Router APIs (`getServerSideProps`, `getStaticProps`, `getInitialProps`)
- Don't add `"use client"` to layout files -- push it to leaf components
- Don't use `useEffect` for data fetching in App Router -- use Server Components
- Don't mix Pages Router (`pages/`) and App Router (`app/`) for the same routes
- Don't use `router.push` for mutations -- use Server Actions
- Don't access `cookies()` or `headers()` without understanding they opt into dynamic rendering
