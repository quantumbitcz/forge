# Vue 3 / Nuxt 3 + REST — API Protocol Binding

## Integration Setup

- Nuxt built-in: use `useFetch` / `$fetch` (Nitro's ofetch) — no additional HTTP library needed
- For client-side-only data fetching with caching: `@tanstack/vue-query` + `VueQueryPlugin`
- Create a typed API client layer (`composables/useApi.ts` or `server/utils/api.ts`) to centralize base URL, headers, and error handling

## Framework-Specific Patterns

### SSR-safe data fetching (useFetch)

```ts
// Runs on server during SSR, hydrates on client — no double-fetch
const { data: users, status, refresh } = await useFetch<User[]>('/api/users', {
  key: 'users-list',
  query: filters,   // reactive: refetches when filters change
})
```

### Client-side mutations ($fetch)

```ts
async function createUser(payload: CreateUserPayload) {
  await $fetch('/api/users', { method: 'POST', body: payload })
  await refresh()  // invalidate the list
}
```

### TanStack Query (client-only, complex caching)

```ts
// main.ts / plugins
import { VueQueryPlugin } from '@tanstack/vue-query'
app.use(VueQueryPlugin)

// composables/useUsers.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/vue-query'

export function useUsers() {
  const queryClient = useQueryClient()

  const { data: users, isPending } = useQuery({
    queryKey: ['users'],
    queryFn: () => $fetch<User[]>('/api/users'),
  })

  const { mutate: createUser } = useMutation({
    mutationFn: (payload: CreateUserPayload) =>
      $fetch<User>('/api/users', { method: 'POST', body: payload }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['users'] }),
  })

  return { users, isPending, createUser }
}
```

### Query key convention
- `[entity]` for lists: `['users']`
- `[entity, id]` for detail: `['users', userId]`
- `[entity, 'list', filters]` for filtered lists

## Scaffolder Patterns

```
composables/
  useUsers.ts              # useFetch wrappers or TanStack Query hooks
  useUser.ts               # single resource fetch by ID
server/
  api/
    users/
      index.get.ts         # GET /api/users — list
      index.post.ts        # POST /api/users — create
      [id].get.ts          # GET /api/users/:id — detail
      [id].put.ts          # PUT /api/users/:id — update
      [id].delete.ts       # DELETE /api/users/:id — delete
  utils/
    db.ts                  # database client (server-only)
```

## Dos

- Use `useFetch` with a stable `key` for all SSR-critical data (prevents hydration mismatch)
- Use `pick` to select only needed fields: reduces payload and reactive overhead
- Use `$fetch` inside server routes — it resolves relative URLs correctly in SSR context
- Colocate query key factories with the composable: `const userKeys = { all: ['users'] as const }`

## Don'ts

- Don't use `axios` in Nuxt 3 unless a third-party SDK requires it — `$fetch` (ofetch) covers all use cases
- Don't call `useFetch` inside event handlers — it must run in setup scope; use `$fetch` for event-triggered requests
- Don't use `useAsyncData` without an explicit key — cache collisions cause subtle bugs
- Don't store server state in `ref()` when `useFetch` cache already holds it — duplication causes stale data issues
