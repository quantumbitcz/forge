# React + Apollo Client / urql GraphQL — API Protocol Binding

## Integration Setup
- Apollo Client: `@apollo/client`; wrap with `<ApolloProvider client={client}>` at root
- urql: `urql` + `@urql/core`; wrap with `<Provider value={client}>`
- Code generation: `@graphql-codegen/cli` + `typescript` + `typescript-operations` + `typescript-react-apollo` (or urql equivalent)
- Config: `codegen.ts` pointing to schema URL/file and `documents: "src/**/*.graphql"`

## Framework-Specific Patterns
- Define operations in `.graphql` files colocated with components; generate typed hooks at build time
- Apollo: use generated `use<OperationName>Query` / `use<OperationName>Mutation` hooks
- urql: use generated hooks or `useQuery({ query: UserDocument, variables: { id } })`
- Cache policies (Apollo): `cache-first` for stable data, `network-only` for real-time, `no-cache` for one-off fetches
- Cache updates after mutations: use `update` option on `useMutation` or `cache.modify` for precise updates
- Fragments: define typed fragments with `gql` + codegen; compose into queries to co-locate data requirements with components
- Error handling: check `data` and `error` from query hooks; wrap with `<ApolloErrorBoundary>` at route level

## Scaffolder Patterns
```
src/
  graphql/
    operations/
      users.graphql          # query/mutation/subscription documents
    fragments/
      userFields.graphql     # reusable fragments
  __generated__/             # codegen output (gitignored or committed per preference)
  hooks/
    useUserQuery.ts          # re-export generated hook with additional logic if needed
  providers/
    ApolloProvider.tsx       # ApolloClient config + ApolloProvider wrapper
codegen.ts                   # graphql-codegen config
```

## Dos
- Run `graphql-codegen --watch` in dev to keep types in sync with schema changes
- Co-locate fragments with the components that consume them; compose at the page level
- Use `fetchPolicy: "cache-and-network"` for lists that should show stale data while refreshing
- Handle loading, error, and empty states explicitly for every query

## Don'ts
- Don't write GraphQL queries as inline template literals in components — use `.graphql` files + codegen
- Don't store remote data in additional `useState` — Apollo/urql cache is the source of truth
- Don't use `refetchQueries` with string names — pass `DocumentNode` references for type safety
- Don't skip error boundaries — unhandled GraphQL errors crash the component tree silently
