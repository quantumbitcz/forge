# Next.js + TypeScript Variant

> TypeScript-specific patterns for Next.js projects. Extends `modules/languages/typescript.md` and `modules/frameworks/nextjs/conventions.md`.

## Page and Layout Prop Types

```ts
// Page with dynamic route params
interface PageProps {
  params: Promise<{ id: string }>
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}

export default async function UserPage({ params, searchParams }: PageProps) {
  const { id } = await params
  // ...
}
```

- `params` and `searchParams` are `Promise<...>` in Next.js 15+ — always `await` them
- For layouts: `params` is a `Promise<...>`; `children` is `React.ReactNode`
- Use `generateStaticParams()` returning `{ id: string }[]` for static route generation

## Server Action Types

```ts
'use server'

import { z } from 'zod'

const UpdateSchema = z.object({
  name: z.string().min(1).max(100),
  email: z.string().email(),
})

type ActionResult =
  | { success: true; data: User }
  | { success: false; error: z.ZodError['flatten'] extends infer T ? T : never }

export async function updateUser(formData: FormData): Promise<ActionResult> {
  const parsed = UpdateSchema.safeParse(Object.fromEntries(formData))
  if (!parsed.success) {
    return { success: false, error: parsed.error.flatten() }
  }
  // ...
}
```

- Always type Server Action return values explicitly
- Use discriminated union `{ success: true; data: T } | { success: false; error: E }` for action results
- Avoid generic `any` in Server Action parameters

## Metadata Types

```ts
import type { Metadata, ResolvingMetadata } from 'next'

export const metadata: Metadata = {
  title: {
    template: '%s | My App',
    default: 'My App',
  },
  description: '...',
}

export async function generateMetadata(
  { params }: PageProps,
  parent: ResolvingMetadata
): Promise<Metadata> {
  const parentTitle = (await parent).title
  return { title: `${item.name} | ${parentTitle}` }
}
```

## Route Handler Types

```ts
import { NextRequest, NextResponse } from 'next/server'

// Typed segment context for dynamic routes
interface Context {
  params: Promise<{ id: string }>
}

export async function GET(
  request: NextRequest,
  context: Context
): Promise<NextResponse> {
  const { id } = await context.params
  return NextResponse.json({ id })
}
```

## Component Typing

- Server Components: plain `async function` returning `JSX.Element | Promise<JSX.Element>`
- Client Components: same as React — no `React.FC`, type props inline or via interface
- Use `React.ReactNode` for `children` in layout components

## Config Types

```ts
import type { NextConfig } from 'next'

const config: NextConfig = {
  images: {
    remotePatterns: [{ protocol: 'https', hostname: 'example.com' }],
  },
}

export default config
```

## Strict Mode

- `strict: true` in `tsconfig.json` — no exceptions
- No `any` — use `unknown` and narrow with type guards or Zod
- TSDoc on all exported Server Actions, Route Handlers, and shared utilities
