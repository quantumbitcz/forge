# GraphQL Conventions

## Overview

GraphQL is a query language and runtime for APIs that gives clients precise control over the data they fetch.
These conventions cover schema design, resolver patterns, pagination, security, and error handling to produce
schemas that are expressive, safe under arbitrary client queries, and evolvable without versioning.

## Architecture Patterns

### Schema Design: Operation Separation

Keep query, mutation, and subscription types cohesive and well-named:

```graphql
type Query {
  user(id: ID!): User
  users(filter: UserFilter, first: Int, after: String): UserConnection!
}

type Mutation {
  createUser(input: CreateUserInput!): CreateUserPayload!
  updateUser(id: ID!, input: UpdateUserInput!): UpdateUserPayload!
  deleteUser(id: ID!): DeleteUserPayload!
}

type Subscription {
  userStatusChanged(userId: ID!): UserStatusEvent!
}
```

Use dedicated payload types for mutations — never return the raw entity:
```graphql
type CreateUserPayload {
  user: User
  errors: [UserError!]!
}
```

### Input Validation with @constraint

```graphql
input CreateUserInput {
  email: String! @constraint(format: "email")
  age:   Int!    @constraint(min: 0, max: 150)
  name:  String! @constraint(minLength: 1, maxLength: 100)
}
```

### Relay Connection Spec (Cursor Pagination)

```graphql
type UserConnection {
  edges:    [UserEdge!]!
  pageInfo: PageInfo!
  totalCount: Int!
}

type UserEdge {
  node:   User!
  cursor: String!
}

type PageInfo {
  hasNextPage:     Boolean!
  hasPreviousPage: Boolean!
  startCursor:     String
  endCursor:       String
}
```

Usage:
```graphql
query {
  users(first: 20, after: "eyJpZCI6MTAwfQ==") {
    edges { node { id name } cursor }
    pageInfo { hasNextPage endCursor }
  }
}
```

## Configuration

### Query Complexity and Depth Limits

Configure at the schema level to prevent abuse:

```javascript
// graphql-query-complexity example
const complexityPlugin = createComplexityPlugin({
  maximumComplexity: 1000,
  variables: {},
  onComplete: (complexity) => console.log("Query complexity:", complexity),
  estimators: [
    fieldExtensionsEstimator(),
    simpleEstimator({ defaultComplexity: 1 }),
  ],
});

// Depth limiting
import depthLimit from "graphql-depth-limit";
const server = new ApolloServer({
  validationRules: [depthLimit(7)],
});
```

### Persisted Queries (APQ)

Reduce payload size and enable server-side query allowlisting:
```json
// Client sends hash first
POST /graphql
{ "extensions": { "persistedQuery": { "version": 1, "sha256Hash": "abc123" } } }

// Server returns 200 with data if cached, or PersistedQueryNotFound
// Client retries with full query + hash; server stores and responds
```

## Performance

### N+1 Resolution with DataLoader

Never call the database once per node in a list resolver. Use batching:

```javascript
// Without DataLoader — N+1 problem
const resolvers = {
  Post: {
    author: (post) => db.users.findById(post.authorId), // called N times
  },
};

// With DataLoader — single batched query
const userLoader = new DataLoader(async (ids) => {
  const users = await db.users.findByIds(ids);
  return ids.map((id) => users.find((u) => u.id === id));
});

const resolvers = {
  Post: {
    author: (post) => userLoader.load(post.authorId),
  },
};
```

Create a new DataLoader instance per request to avoid cross-request cache pollution.

### Subscriptions (WebSocket Transport)

```graphql
# Schema
type Subscription {
  messageAdded(channelId: ID!): Message!
}
```

```javascript
// Server (graphql-ws)
import { useServer } from "graphql-ws/lib/use/ws";
useServer({ schema }, wsServer);

// Client
const client = createClient({ url: "wss://api.example.com/graphql" });
const unsubscribe = client.subscribe(
  { query: `subscription { messageAdded(channelId: "c1") { id text } }` },
  { next: (data) => console.log(data), error: console.error, complete: () => {} }
);
```

## Security

### Error Handling: errors vs Data Nullability

Business errors belong in the payload, not in the top-level `errors` array:
```graphql
# Preferred — typed error in payload
type DeleteUserPayload {
  success: Boolean!
  errors: [UserError!]!
}

type UserError {
  field: String
  message: String!
  code: UserErrorCode!
}
```

Top-level `errors` should surface only unexpected server failures. Mask internal
details in production:
```javascript
formatError: (error) => {
  if (error.originalError instanceof InternalError) {
    return new GraphQLError("Internal server error", { extensions: { code: "INTERNAL_ERROR" } });
  }
  return error;
};
```

## Federation for Microservices

```graphql
# users-service schema
type User @key(fields: "id") {
  id: ID!
  name: String!
  email: String!
}

# orders-service schema
type Order {
  id: ID!
  user: User! # resolved via federation reference resolver
}

extend type User @key(fields: "id") {
  id: ID! @external
  orders: [Order!]!
}
```

Prefer federation over schema stitching for independent service deployability.

## Testing

```
# Schema tests
- Every query/mutation/subscription has at least one positive test
- Input validation: test @constraint boundaries (min, max, format)
- Depth limit: query exceeding maxDepth returns error, not 500
- Complexity limit: expensive query rejected with COMPLEXITY_LIMIT_EXCEEDED

# Resolver tests
- DataLoader batching: assert single DB call for list resolver
- Auth: unauthenticated request to protected field returns UNAUTHENTICATED
- Null propagation: nullable fields return null, non-null fields throw on error

# Subscription tests
- Subscribe → trigger mutation → assert event received
- Disconnect → reconnect → no duplicate events
```

## Dos

- Use Relay connection spec for all paginated lists
- Put business errors in mutation payload types, not top-level `errors`
- Use DataLoader for every resolver that fetches by foreign key
- Set query complexity and depth limits before going to production
- Use persisted queries to reduce payload size and enable allowlisting
- Use federation when scaling to multiple services; avoid runtime stitching
- Version inputs (`CreateUserInput`) separately from output types (`User`)

## Don'ts

- Don't expose raw database IDs directly — use opaque or namespaced IDs
- Don't resolve child entities inside parent resolvers — use dedicated resolvers
- Don't return internal stack traces in the `errors` array in production
- Don't create one DataLoader globally — it leaks data across requests
- Don't use subscriptions for request-response patterns; use queries/mutations
- Don't add nullable wrappers to fields that can never be null — misleads clients
- Don't allow unlimited query depth or complexity without a configured guard
