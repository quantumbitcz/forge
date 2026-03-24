# Spring GraphQL — API Protocol Binding

## Integration Setup
- Add `spring-boot-starter-graphql` (includes `graphql-java` + Spring integration)
- Place schema files in `src/main/resources/graphql/*.graphqls` — auto-discovered
- Enable GraphiQL: `spring.graphql.graphiql.enabled=true` (dev profile only)
- For subscriptions: add `spring-boot-starter-websocket`

## Framework-Specific Patterns
- Use schema-first design: define `.graphqls` schema before writing resolvers
- Annotate resolver methods with `@SchemaMapping(typeName="Query", field="user")`; or use `@QueryMapping`/`@MutationMapping` shortcuts
- For N+1 prevention use `@BatchMapping`: method receives `List<ParentType>` and returns `Map<ParentType, ChildType>`
- Subscriptions: annotate with `@SubscriptionMapping`; return `Flux<T>`
- Inject `DataFetchingEnvironment` for field selection info; avoid over-fetching
- Exception handling: implement `DataFetcherExceptionResolver`; map domain exceptions to `GraphQLError`
- Security: apply `@PreAuthorize` on resolver methods; works with Spring Security integration

## Scaffolder Patterns
```
src/main/
  resources/graphql/
    schema.graphqls            # type definitions, queries, mutations, subscriptions
  kotlin/com/example/
    web/graphql/
      UserController.kt        # @QueryMapping, @MutationMapping resolvers
      UserBatchLoader.kt       # @BatchMapping for associations
      SubscriptionController.kt
    config/
      GraphQlConfig.kt         # RuntimeWiringConfigurer if needed
    exception/
      GraphQlExceptionHandler.kt  # DataFetcherExceptionResolverAdapter
```

## Dos
- Define the schema first; generate client types from schema if needed with `graphql-codegen`
- Use `@BatchMapping` for any parent → children relationship to avoid N+1
- Return proper GraphQL errors (not HTTP 500) via `DataFetcherExceptionResolver`
- Limit query depth and complexity via `graphql-java` instrumentation in config

## Don'ts
- Don't use code-first schema generation in production — schema-first is required here
- Don't return raw JPA entities from resolvers; use response projections
- Don't expose GraphiQL in production profiles
- Don't block inside subscription `Flux` publishers
