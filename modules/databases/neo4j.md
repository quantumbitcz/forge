# Neo4j Best Practices

## Overview
Neo4j is a native graph database optimized for traversing relationships between entities. Use it for social networks, recommendation engines, knowledge graphs, fraud detection, identity and access management, and any domain where relationships are first-class citizens. Avoid Neo4j for tabular analytics (use ClickHouse/PostgreSQL), simple key-value lookups (use Redis), or when your data has no meaningful relationship traversals.

## Architecture Patterns

**Property graph model — nodes, relationships, and properties:**
```cypher
// Create a social graph
CREATE (alice:User {name: 'Alice', email: 'alice@example.com'})
CREATE (bob:User {name: 'Bob', email: 'bob@example.com'})
CREATE (post:Post {title: 'Graph Databases', createdAt: datetime()})
CREATE (alice)-[:FOLLOWS]->(bob)
CREATE (alice)-[:AUTHORED]->(post)
CREATE (bob)-[:LIKED {at: datetime()}]->(post)
```

**Index-free adjacency — traversals are O(1) per hop:**
```cypher
// Friends-of-friends — constant cost per relationship, regardless of graph size
MATCH (me:User {id: $userId})-[:FOLLOWS*2]->(fof:User)
WHERE NOT (me)-[:FOLLOWS]->(fof) AND me <> fof
RETURN DISTINCT fof.name LIMIT 20
```

**Shortest path algorithms:**
```cypher
MATCH path = shortestPath(
  (a:User {id: $fromId})-[:FOLLOWS*..10]-(b:User {id: $toId})
)
RETURN path, length(path)
```

**Full-text search index:**
```cypher
CREATE FULLTEXT INDEX userSearch FOR (u:User) ON EACH [u.name, u.bio];
CALL db.index.fulltext.queryNodes('userSearch', 'alice') YIELD node, score
RETURN node.name, score
```

**Anti-pattern — supernodes (millions of relationships on one node):** A celebrity node with 10M followers makes traversals through it expensive. Use relationship properties to filter early, or denormalize follower counts.

## Configuration

**Development (`neo4j.conf`):**
```properties
server.memory.heap.initial_size=512m
server.memory.heap.max_size=1g
server.memory.pagecache.size=512m
dbms.security.auth_enabled=true
```

**Production tuning:**
```properties
# Page cache: should fit the entire graph store if possible
server.memory.pagecache.size=16g
# Heap: 8-16 GB typically sufficient; larger heaps increase GC pauses
server.memory.heap.initial_size=8g
server.memory.heap.max_size=8g
# Transaction log retention for backup
db.tx_log.rotation.retention_policy=7 days
# Bolt connector
server.bolt.listen_address=:7687
server.bolt.advertised_address=neo4j.internal:7687
```

**Connection (Bolt protocol):**
```
bolt://neo4j.internal:7687
neo4j://neo4j.internal:7687  # routing-aware for clusters
```

## Performance

**Profile queries with PROFILE/EXPLAIN:**
```cypher
PROFILE MATCH (u:User)-[:FOLLOWS]->(f)
WHERE u.id = $userId
RETURN f.name
```
Look for: `AllNodesScan` (missing index), `Eager` operators (pipeline breaks), high `DbHits`.

**Create indexes for lookup properties:**
```cypher
CREATE INDEX FOR (u:User) ON (u.id);
CREATE INDEX FOR (u:User) ON (u.email);
CREATE CONSTRAINT FOR (u:User) REQUIRE u.id IS UNIQUE;
```

**Parameterized queries (enables query plan caching):**
```cypher
// GOOD: parameterized — plan is cached
MATCH (u:User {id: $userId}) RETURN u

// BAD: string concatenation — new plan compiled every time
MATCH (u:User {id: '${userId}'}) RETURN u
```

**Batch writes with UNWIND:**
```cypher
UNWIND $users AS userData
CREATE (u:User) SET u = userData
```

**Avoid variable-length unbounded paths:** `[:FOLLOWS*]` without upper bound traverses the entire connected component. Always set bounds: `[:FOLLOWS*1..5]`.

## Security

**Authentication and role-based access:**
```cypher
CREATE USER app_user SET PASSWORD 'strong-password' SET PASSWORD CHANGE NOT REQUIRED;
CREATE ROLE app_reader;
GRANT MATCH {*} ON GRAPH mydb TO app_reader;
GRANT ROLE app_reader TO app_user;
```

**Never expose Bolt (7687) or HTTP (7474) ports to the internet.** Use VPC + TLS:
```properties
dbms.ssl.policy.bolt.enabled=true
dbms.ssl.policy.bolt.base_directory=certificates/bolt
```

**Parameterized Cypher prevents injection:** Always use `$param` syntax — never concatenate user input into Cypher strings.

## Testing

Use **Testcontainers** for integration tests:
```java
@Container
static Neo4jContainer<?> neo4j = new Neo4jContainer<>("neo4j:5")
    .withAdminPassword("test");

@BeforeEach
void setUp() {
    driver = GraphDatabase.driver(neo4j.getBoltUrl(), AuthTokens.basic("neo4j", "test"));
}
```

For unit tests, use the Neo4j embedded test harness or mock the driver. Use `CALL db.clearDatabase()` between tests to ensure isolation. Test graph constraints (uniqueness, existence) explicitly.

## Dos
- Model your domain as a graph: nodes are nouns, relationships are verbs, properties are adjectives.
- Use labels liberally — they're like indexes for node categories and make queries faster.
- Always parameterize Cypher queries — enables plan caching and prevents injection.
- Use `MERGE` for idempotent creates — avoids duplicate nodes/relationships.
- Batch large imports with `UNWIND` or `neo4j-admin database import` — single-record creates are slow at scale.
- Use `APOC` procedures for advanced operations (batching, data import, graph algorithms).
- Set upper bounds on variable-length paths to prevent runaway traversals.

## Don'ts
- Don't model everything as a relationship — if you never traverse it, it's just a property.
- Don't use Neo4j as a general-purpose relational database — tabular queries with GROUP BY and aggregation are better in PostgreSQL.
- Don't create unbounded variable-length paths (`*`) — always set upper bounds (`*1..10`).
- Don't store large binary data (images, files) as node properties — use external storage with a reference.
- Don't skip indexes on frequently queried node properties — without indexes, every query does a full label scan.
- Don't use the HTTP API for high-throughput operations — use the Bolt protocol for lower overhead and binary transport.
- Don't embed application logic in Cypher procedures — keep business logic in the application layer, use Cypher for data access.
