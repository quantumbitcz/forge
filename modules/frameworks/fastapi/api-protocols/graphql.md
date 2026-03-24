# FastAPI + Strawberry GraphQL — API Protocol Binding

## Integration Setup
- Add `strawberry-graphql[fastapi]`; mount router: `app.include_router(strawberry.fastapi.GraphQLRouter(schema))`
- For subscriptions: also add `strawberry-graphql[websockets]`
- DataLoader support built-in via `strawberry.dataloader.DataLoader`

## Framework-Specific Patterns
- Define types with `@strawberry.type`, `@strawberry.input`, `@strawberry.enum` decorators
- Root resolver methods in `@strawberry.type` classes named `Query`, `Mutation`, `Subscription`
- Schema created via `strawberry.Schema(query=Query, mutation=Mutation, subscription=Subscription)`
- Dependency injection: use `strawberry.fastapi.BaseContext` subclass; inject FastAPI `Depends()` via `get_context`
- DataLoader: instantiate per request in context; call `await loader.load(id)` inside resolvers
- Subscriptions: resolver returns `AsyncGenerator[T, None]`; backed by `async for` over async queue or stream
- Error handling: raise `strawberry.exceptions.StrawberryGraphQLError` or return union types with error variants

## Scaffolder Patterns
```
app/
  graphql/
    schema.py              # strawberry.Schema assembly
    types/
      user.py              # @strawberry.type definitions
    resolvers/
      query.py             # @strawberry.type Query class
      mutation.py          # @strawberry.type Mutation class
      subscription.py
    loaders/
      user_loader.py       # DataLoader per entity
    context.py             # BaseContext subclass with loaders + db session
  main.py                  # GraphQLRouter mount
```

## Dos
- Use DataLoaders for all relationship fields to avoid N+1 queries
- Return typed union errors (`Success | NotFoundError`) rather than raising exceptions for expected failure cases
- Set `graphql_ide=None` in production; use `graphql_ide="graphiql"` in dev
- Use `strawberry.ID` for entity identifiers; it serializes as a string

## Don'ts
- Don't put database calls directly in type resolver methods — delegate to a service/repository
- Don't share DataLoader instances across requests; instantiate fresh per request in context
- Don't skip input validation — use `strawberry.input` with `pydantic` validator integration when needed
- Don't expose introspection in production without auth guard
