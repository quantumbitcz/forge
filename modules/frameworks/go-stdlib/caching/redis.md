# Go stdlib + Redis (go-redis)

> Go stdlib Redis patterns using `go-redis/redis`. Extends generic Go conventions.

## Integration Setup

```go
// go.mod
require github.com/redis/go-redis/v9 v9.5.0
```

```go
import "github.com/redis/go-redis/v9"
```

## Client Setup

```go
func NewRedisClient(addr, password string, db int) *redis.Client {
    rdb := redis.NewClient(&redis.Options{
        Addr:         addr,     // "localhost:6379"
        Password:     password,
        DB:           db,
        PoolSize:     10,
        MinIdleConns: 2,
        DialTimeout:  5 * time.Second,
        ReadTimeout:  3 * time.Second,
        WriteTimeout: 3 * time.Second,
    })
    return rdb
}
```

## Cache-Aside Pattern

```go
func GetUser(ctx context.Context, rdb *redis.Client, db UserStore, id string) (*User, error) {
    cacheKey := "user:" + id

    // 1. Try cache
    cached, err := rdb.Get(ctx, cacheKey).Bytes()
    if err == nil {
        var u User
        if jsonErr := json.Unmarshal(cached, &u); jsonErr == nil {
            return &u, nil
        }
    } else if !errors.Is(err, redis.Nil) {
        slog.Warn("redis get failed", "err", err) // cache miss on error, continue to DB
    }

    // 2. Load from DB
    user, err := db.GetByID(ctx, id)
    if err != nil {
        return nil, err
    }

    // 3. Populate cache — fire-and-forget; don't block on cache write failure
    if data, jsonErr := json.Marshal(user); jsonErr == nil {
        _ = rdb.Set(ctx, cacheKey, data, 10*time.Minute).Err()
    }

    return user, nil
}

func InvalidateUser(ctx context.Context, rdb *redis.Client, id string) error {
    return rdb.Del(ctx, "user:"+id).Err()
}
```

## Pipeline Commands

```go
// Batch multiple commands in a single round-trip
func SetMultiple(ctx context.Context, rdb *redis.Client, items map[string]any, ttl time.Duration) error {
    pipe := rdb.Pipeline()
    for k, v := range items {
        data, _ := json.Marshal(v)
        pipe.Set(ctx, k, data, ttl)
    }
    _, err := pipe.Exec(ctx)
    return err
}
```

## Pub/Sub

```go
func Subscribe(ctx context.Context, rdb *redis.Client, channel string, handler func(string)) {
    sub := rdb.Subscribe(ctx, channel)
    defer sub.Close()

    ch := sub.Channel()
    for {
        select {
        case msg, ok := <-ch:
            if !ok {
                return
            }
            handler(msg.Payload)
        case <-ctx.Done():
            return
        }
    }
}
```

## Scaffolder Patterns

```yaml
patterns:
  client_setup: "internal/cache/redis.go"
  cache_service: "internal/cache/{entity}_cache.go"
```

## Additional Dos/Don'ts

- DO treat Redis errors as cache-miss on reads — never let Redis unavailability cause a hard failure
- DO always set TTL on `Set` calls — unbounded keys exhaust memory
- DO use pipelines for bulk operations to minimize round-trips
- DO check for `redis.Nil` specifically when a miss is expected (e.g., key not found)
- DON'T store large objects (>100KB) directly in Redis — store identifiers and load from primary store
- DON'T use `KEYS *` pattern scanning in production — use `SCAN` with a cursor instead
- DON'T reuse a `redis.Pipeliner` across goroutines — pipelines are not thread-safe
