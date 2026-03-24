# Express + Apollo Server GraphQL — API Protocol Binding

## Integration Setup
- Add `@apollo/server` + `@as-integrations/express` (Apollo Server 4); mount via `expressMiddleware`
- Add `graphql` peer dependency; `@graphql-tools/schema` for schema merging
- DataLoader: `dataloader` package; instantiate per request in context factory
- Apollo Studio: enabled by default in non-production; set `introspection: false` in production

## Framework-Specific Patterns
- Schema-first: define SDL in `.graphql` files; load with `@graphql-tools/load` or `loadFilesSync`
- Resolvers in separate files by type; merged into a single resolver map with `mergeResolvers`
- Context function passed to `expressMiddleware`: extract auth token, build DataLoaders, attach db connection
- DataLoader: one loader per entity relation; batch function receives array of keys, returns same-length array
- Error handling: throw `GraphQLError` with `extensions.code`; Apollo formats it per spec
- Subscriptions: use `graphql-ws` library with a separate WebSocket server (not Apollo's deprecated `subscriptions-transport-ws`)

## Scaffolder Patterns
```
src/
  graphql/
    schema/
      user.graphql           # SDL type definitions
    resolvers/
      user.resolver.ts       # resolver map for User type
      query.resolver.ts
      mutation.resolver.ts
    dataloaders/
      user.loader.ts         # DataLoader factory
    context.ts               # ApolloContext type + context factory function
  server.ts                  # Apollo + Express wiring
```

## Dos
- Use DataLoaders for every parent → child relationship to batch database lookups
- Set `formatError` in Apollo config to sanitize internal errors before sending to clients
- Use `extensions.code` on `GraphQLError` for machine-readable error classification
- Enable persisted queries in production to reduce payload size

## Don'ts
- Don't use Apollo Server 3 or the deprecated `apollo-server-express` package in new projects
- Don't share DataLoader instances across requests — instantiate fresh per request in context
- Don't disable `introspection` in development; disable it in production
- Don't put business logic in resolvers — delegate to service layer
