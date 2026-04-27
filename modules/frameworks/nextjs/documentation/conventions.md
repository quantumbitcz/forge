# Next.js Documentation Conventions

> Support tier: community

> Extends `modules/documentation/conventions.md` with Next.js-specific patterns.

## Code Documentation

- Use TSDoc (`/** */`) for all exported Server Components, Client Components, API route handlers, and custom hooks.
- Server Components: document what data they fetch, any `Suspense` boundaries they wrap, and revalidation behavior.
- Client Components (`'use client'`): document why client-side rendering is required. Prefer Server Components by default.
- API routes (`app/api/**/route.ts`): document HTTP method, request body shape, response shape, and auth requirements.
- Server Actions: document the mutation performed, validation applied, and `revalidatePath`/`revalidateTag` calls.

```typescript
/**
 * Renders the user profile page with coaching statistics.
 *
 * Server Component — fetches user data and session history on the server.
 * Wrapped in Suspense in the parent layout; shows skeleton during load.
 *
 * @param params - Route params including `userId`
 */
export default async function ProfilePage({ params }: { params: { userId: string } }) { ... }
```

## Architecture Documentation

- Document the App Router structure for projects with 10+ routes — include a route tree or table.
- Document the rendering strategy per route group: SSR, SSG, ISR, or Client. Include revalidation periods for ISR routes.
- Document Middleware (`middleware.ts`): what it matches, what it checks (auth, geolocation, feature flags), and redirect/rewrite behavior.
- Document the caching strategy: `fetch` cache options, `unstable_cache` usage, and `revalidateTag` taxonomy.
- Document `next.config.js` non-default options with a comment explaining each.

## Diagram Guidance

- **Route tree:** Mermaid flowchart showing route groups, layouts, and page hierarchy.
- **Data fetching flow:** Sequence diagram showing Server Component → fetch → cache → render.

## Dos

- Document `'use client'` boundary placement decisions — they have performance implications
- Document `revalidateTag` taxonomy — tag names are a contract between mutations and cached data
- Keep `next.config.js` comments — configuration options are not self-explanatory

## Don'ts

- Don't document Next.js built-in file conventions (`layout.tsx`, `loading.tsx`) — document your project's usage of them
- Don't maintain a manual API reference alongside the OpenAPI spec for API routes
