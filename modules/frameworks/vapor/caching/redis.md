# Redis Caching with Vapor

## Integration Setup

```swift
// Package.swift
.package(url: "https://github.com/vapor/redis.git", from: "4.10.0"),
// targets:
.product(name: "Redis", package: "redis"),
```

```swift
// configure.swift
try app.caches.use(.redis(
    url: Environment.get("REDIS_URL") ?? "redis://localhost:6379"
))
// Or with explicit configuration
app.redis.configuration = try .init(
    hostname: "localhost",
    port:     6379,
    password: Environment.get("REDIS_PASSWORD"),
    database: 0,
    pool:     .init(maximumConnectionCount: 10, minimumConnectionCount: 1)
)
```

## Framework-Specific Patterns

### Request-Level Cache
```swift
// Get / set via req.cache (uses default cache backend)
let cached = try await req.cache.get("user:\(userID)", as: UserResponse.self)
if let cached { return cached }

let user = try await User.find(userID, on: req.db)?.toResponse()
    ?? { throw Abort(.notFound) }()
try await req.cache.set("user:\(userID)", to: user, expiresIn: .minutes(15))
return user
```

### Direct Redis Client (Advanced)
```swift
// Low-level RedisClient for data structures unavailable via Cache API
let count = try await req.redis.increment("rate_limit:\(userID)")
try await req.redis.expire("rate_limit:\(userID)", after: .seconds(60))

// Pub/Sub for real-time features
try await req.redis.publish("events", message: RESPValue(from: payload))
```

### Session Storage
```swift
// configure.swift — store sessions in Redis
app.sessions.use(.redis)
app.middleware.use(app.sessions.middleware)
```

## Scaffolder Patterns

```yaml
patterns:
  configure: "Sources/App/configure.swift"
  cache_service: "Sources/App/Services/{Entity}CacheService.swift"
```

## Additional Dos/Don'ts

- DO use namespaced keys (`entity:id:field`) to avoid collisions across services
- DO always set TTL on cache entries; never store indefinitely without an eviction strategy
- DO use `req.cache` for simple key-value caching; use `req.redis` directly for complex data structures
- DO handle cache misses gracefully — treat Redis as optional, not required for correctness
- DON'T store sensitive data (tokens, PII) in Redis without encryption at rest
- DON'T use Redis as a primary datastore; it is a cache — data loss on restart is expected without persistence config
- DON'T ignore connection errors from Redis; log and fall through to the database
