# Svelte 5 + TanStack Svelte Query REST — API Protocol Binding

## Integration Setup

```bash
npm install @tanstack/svelte-query @tanstack/svelte-query-devtools
```

Wrap the app root with `QueryClientProvider`:

```svelte
<!-- src/App.svelte -->
<script lang="ts">
  import { QueryClient, QueryClientProvider } from '@tanstack/svelte-query';
  import { SvelteQueryDevtools } from '@tanstack/svelte-query-devtools';

  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { staleTime: 5 * 60 * 1000 },
    },
  });
</script>

<QueryClientProvider client={queryClient}>
  <!-- app content -->
  <SvelteQueryDevtools />
</QueryClientProvider>
```

## Framework-Specific Patterns

- `createQuery({ queryKey: ['users', filters], queryFn: () => api.users.list(filters) })` for GET operations
- `createMutation({ mutationFn: api.users.create, onSuccess: () => queryClient.invalidateQueries({ queryKey: ['users'] }) })` for mutations
- Query key convention: `[entity, ...params]` — e.g., `['users', userId]`, `['users', 'list', filters]`
- Cache invalidation: `queryClient.invalidateQueries` after mutations; use `setQueryData` for optimistic updates
- Optimistic updates: `onMutate` sets temporary data + returns rollback snapshot; `onError` calls rollback
- Error handling: errors propagate to `$query.error`; display in component `{#if $query.isError}` blocks
- Prefetching: `queryClient.prefetchQuery` in parent components for perceived performance

```svelte
<!-- src/components/UserList.svelte -->
<script lang="ts">
  import { createQuery } from '@tanstack/svelte-query';
  import { userKeys, api } from '../api/users.api.ts';

  const query = createQuery({
    queryKey: userKeys.all,
    queryFn: api.users.list,
  });
</script>

{#if $query.isPending}
  <LoadingSpinner />
{:else if $query.isError}
  <ErrorMessage message={$query.error.message} />
{:else}
  {#each $query.data as user (user.id)}
    <UserCard {user} />
  {/each}
{/if}
```

## Typed API Client

```typescript
// src/api/client.ts
const BASE_URL = import.meta.env.VITE_API_BASE_URL;

export async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${BASE_URL}${path}`, {
    headers: { 'Content-Type': 'application/json', ...init?.headers },
    ...init,
  });
  if (!response.ok) throw new Error(`API error ${response.status}: ${await response.text()}`);
  return response.json() as Promise<T>;
}
```

```typescript
// src/api/users.api.ts
import { apiFetch } from './client.ts';
import type { User } from '../types/user.ts';

export const userKeys = {
  all: ['users'] as const,
  detail: (id: string) => [...userKeys.all, id] as const,
  list: (filters: Record<string, string>) => [...userKeys.all, 'list', filters] as const,
};

export const api = {
  users: {
    list: () => apiFetch<User[]>('/users'),
    get: (id: string) => apiFetch<User>(`/users/${id}`),
    create: (body: Omit<User, 'id'>) => apiFetch<User>('/users', { method: 'POST', body: JSON.stringify(body) }),
    update: (id: string, body: Partial<User>) => apiFetch<User>(`/users/${id}`, { method: 'PUT', body: JSON.stringify(body) }),
    delete: (id: string) => apiFetch<void>(`/users/${id}`, { method: 'DELETE' }),
  },
};
```

## Scaffolder Patterns

```
src/
  api/
    client.ts                   # typed fetch wrapper with error handling
    users.api.ts                # api.users.list/get/create/update/delete + key factories
  components/
    users/
      UserList.svelte           # createQuery consumer
      UserForm.svelte           # createMutation consumer
```

## Dos

- Colocate query key factories with the API module: `export const userKeys = { all: ['users'] as const, detail: (id) => [...userKeys.all, id] as const }`
- Use `staleTime` to avoid unnecessary refetches for stable data (e.g., reference data, user profiles)
- Use `select` to transform or filter data inside `createQuery` without changing the cache
- Use `$query.isPending` (not `$query.isLoading`) when checking for the initial load state

## Don'ts

- Don't store server state in `$state` — use TanStack Query cache as the source of truth
- Don't construct query keys inline with object literals — use key factories for consistency
- Don't call `queryClient.invalidateQueries` with an empty key (invalidates everything)
- Don't ignore mutation error states — always surface errors to the user
- Don't access `import.meta.env` outside of `src/api/` — keep environment coupling localized
