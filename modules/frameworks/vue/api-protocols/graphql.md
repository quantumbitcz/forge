# Vue 3 / Nuxt 3 + GraphQL — API Protocol Binding

## Integration Setup

- **Recommended**: `@vue/apollo-composable` + `@apollo/client` + `@nuxtjs/apollo` Nuxt module
- **Alternative**: `villus` (lightweight Vue-first GraphQL client with built-in Nuxt integration)
- Code generation: `@graphql-codegen/cli` + `typescript` + `typescript-operations` + `typescript-vue-apollo` (or villus equivalent)
- Config: `codegen.ts` pointing to schema URL/file and `documents: "**/*.graphql"`

## Framework-Specific Patterns

### Apollo with @nuxtjs/apollo

```ts
// nuxt.config.ts
export default defineNuxtConfig({
  modules: ['@nuxtjs/apollo'],
  apollo: {
    clients: {
      default: { httpEndpoint: process.env.GRAPHQL_URL },
    },
  },
})
```

```ts
// composables/useUserQuery.ts — using generated hook
import { useUserQuery } from '~/graphql/generated'

export function useUser(id: Ref<string>) {
  const { result, loading, error } = useUserQuery({ id })
  const user = computed(() => result.value?.user ?? null)
  return { user, loading, error }
}
```

### Villus (alternative)

```ts
// plugins/villus.ts
import { createClient, defaultPlugins } from 'villus'
export default defineNuxtPlugin((nuxtApp) => {
  const client = createClient({ url: useRuntimeConfig().public.graphqlUrl })
  nuxtApp.vueApp.use(client)
})

// composables/useUsers.ts
import { useQuery } from 'villus'

export function useUsers() {
  const { data, fetching, error } = useQuery({
    query: `query { users { id name email } }`,
  })
  return { users: computed(() => data.value?.users ?? []), fetching, error }
}
```

### Typed operations with codegen

```ts
// Prefer generated hooks over inline query strings
import { useGetUserQuery, useUpdateUserMutation } from '~/graphql/generated'

const { result, loading } = useGetUserQuery({ variables: { id: props.userId } })
const { mutate: updateUser } = useUpdateUserMutation()

async function save(input: UpdateUserInput) {
  await updateUser({ variables: { id: props.userId, input } })
}
```

### Cache updates after mutations (Apollo)

```ts
const { mutate } = useCreatePostMutation({
  update(cache, { data }) {
    cache.modify({
      fields: {
        posts(existing = []) {
          return [...existing, cache.writeFragment({ data: data.createPost, fragment: PostFragment })]
        }
      }
    })
  }
})
```

## Scaffolder Patterns

```
graphql/
  operations/
    users.graphql          # query/mutation/subscription documents
  fragments/
    userFields.graphql     # reusable fragments
  generated/               # codegen output (gitignored or committed per preference)
    index.ts               # all generated hooks and types
composables/
  useUserQuery.ts          # re-export generated hook with domain logic
plugins/
  apollo.ts                # ApolloClient / villus setup
codegen.ts                 # graphql-codegen config
```

## Dos

- Run `graphql-codegen --watch` in dev to keep types in sync with schema changes
- Co-locate fragments with the components that consume them; compose at the page level
- Handle loading, error, and empty states explicitly for every query
- Use `fetchPolicy: "cache-and-network"` for lists that should show stale data while refreshing

## Don'ts

- Don't write GraphQL queries as inline template literals — use `.graphql` files + codegen
- Don't store remote data in additional `ref()` — Apollo/villus cache is the source of truth
- Don't skip error boundaries — unhandled GraphQL errors silently leave the UI in a broken state
- Don't use `refetchQueries` with string names — pass `DocumentNode` references for type safety
