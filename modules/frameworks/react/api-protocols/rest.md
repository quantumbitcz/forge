# React + TanStack Query REST — API Protocol Binding

## Integration Setup
- Add `@tanstack/react-query` + `@tanstack/react-query-devtools`
- Wrap app in `<QueryClientProvider client={queryClient}>` at root
- Create a typed API client layer (fetch wrapper or `axios` instance) separate from query hooks

## Framework-Specific Patterns
- `useQuery({ queryKey: ["users", filters], queryFn: () => api.users.list(filters) })` for GET operations
- `useMutation({ mutationFn: api.users.create, onSuccess: () => queryClient.invalidateQueries({ queryKey: ["users"] }) })`
- Query key convention: `[entity, ...params]` — e.g., `["users", userId]`, `["users", "list", filters]`
- Cache invalidation: `queryClient.invalidateQueries` after mutations; use `setQueryData` for optimistic updates
- Optimistic updates: `onMutate` sets temporary data + returns rollback snapshot; `onError` calls rollback
- Error handling: errors propagate to `useQuery.error`; wrap route-level components with `<QueryErrorResetBoundary>`
- Prefetching: `queryClient.prefetchQuery` in loaders or parent components for perceived performance

## Scaffolder Patterns
```
src/
  api/
    client.ts              # typed fetch/axios wrapper with auth headers
    users.api.ts           # api.users.list/get/create/update/delete functions
  hooks/
    useUsers.ts            # useQuery wrapper with typed return
    useCreateUser.ts       # useMutation wrapper
  providers/
    QueryProvider.tsx      # QueryClientProvider + DevTools
```

## Dos
- Colocate query key factories with the API module: `export const userKeys = { all: ["users"] as const, detail: (id: string) => [...userKeys.all, id] as const }`
- Use `staleTime` to avoid unnecessary refetches for stable data (e.g., `staleTime: 5 * 60 * 1000`)
- Use `select` to transform or filter data inside `useQuery` without changing the cache
- Suspend queries at page level with `useSuspenseQuery` and React `<Suspense>` boundaries

## Don'ts
- Don't store server state in React `useState` — use TanStack Query cache as the source of truth
- Don't construct query keys inline with object literals — use key factories for consistency
- Don't call `queryClient.invalidateQueries` with an empty key (invalidates everything)
- Don't ignore mutation error states — always surface errors to the user
