# Redis — Caching Best Practices

## Overview

This file covers Redis as a **cache layer** — ephemeral, non-authoritative, with no persistence
requirements. Distinct from using Redis as a primary data store (see `modules/databases/redis.md`).
Use Redis cache for hot read paths, session tokens, rate-limit windows, computed aggregations, and
HTML fragment caches. Never treat the cache as the source of truth — the underlying store must be
able to reconstruct any evicted value.

## Architecture Patterns

### Cache-Aside (Lazy Population)
```python
def get_user(user_id: str) -> User:
    cached = redis.get(f"user:{user_id}")
    if cached:
        return deserialize(cached)
    user = db.find_user(user_id)      # miss: read from DB
    redis.setex(f"user:{user_id}", 300, serialize(user))  # populate
    return user
```
Cache-aside is the default pattern. The application drives population; Redis is never written to
directly by the source of truth.

### Write-Through
```python
def update_user(user_id: str, data: dict) -> User:
    user = db.update_user(user_id, data)          # write to DB first
    redis.setex(f"user:{user_id}", 300, serialize(user))  # sync cache
    return user
```
Write-through keeps the cache warm after writes but doubles write latency. Use for write-heavy
objects that are read immediately after mutation (e.g., user profile updates).

### Write-Behind (Write-Back)
Buffer writes in Redis and flush to the DB asynchronously. Reduces write latency but risks data
loss if Redis crashes before the flush. Only appropriate when some data loss is acceptable (e.g.,
view counters, analytics totals). Implement flush via a background job reading a Redis List/Stream.

### Cache Stampede Prevention

**Locking (mutex on miss):**
```python
lock_key = f"lock:user:{user_id}"
if redis.set(lock_key, "1", nx=True, ex=5):   # acquire lock
    user = db.find_user(user_id)
    redis.setex(f"user:{user_id}", 300, serialize(user))
    redis.delete(lock_key)
else:
    time.sleep(0.05)
    return get_user(user_id)                   # retry — lock holder will populate
```

**Probabilistic early expiration (XFetch):**
```python
import math, random, time

def get_with_xfetch(key: str, ttl: int, beta: float = 1.0):
    value, expiry = redis.get_with_expiry(key)
    remaining = expiry - time.time()
    if remaining - beta * math.log(random.random()) * ttl < 0:
        return None   # trigger early recompute before expiry
    return value
```

### Key Naming Conventions
```
{service}:{entity}:{id}           user-svc:user:42
{service}:{entity}:{id}:{field}   user-svc:user:42:permissions
{service}:rate:{action}:{id}      api:rate:login:192.168.1.1
{service}:lock:{resource}:{id}    order-svc:lock:inventory:sku-99
{service}:session:{token}         auth-svc:session:abc123
```
Prefix with service name to namespace across shared Redis instances.

## Configuration

**Eviction policies for pure cache:**
```conf
maxmemory 2gb
maxmemory-policy allkeys-lru     # evict least recently used across all keys
# Alternative: allkeys-lfu       # better for skewed access (most keys rarely hit)
# volatile-lru                   # only evict keys that have a TTL (mixed use clusters)
```

**Disable persistence for cache-only nodes:**
```conf
save ""                           # disable RDB snapshots
appendonly no                     # disable AOF
```

**Serialization tradeoffs:**
- JSON: human-readable, debuggable with `redis-cli`, 20-40% larger than binary formats.
- MessagePack: compact binary, ~30% smaller than JSON, language-agnostic.
- Protobuf: smallest, fastest deserialization, requires schema management.
- Use JSON in development/staging; MessagePack or Protobuf in high-throughput production.

## Performance

- Set `maxmemory` — without it Redis consumes all available RAM on cache misses that load from DB.
- Use `MGET` / `MSET` for multi-key lookups rather than looping `GET` calls.
- Pipeline commands within a request to reduce round-trips:
  ```python
  pipe = redis.pipeline()
  for key in keys:
      pipe.get(key)
  values = pipe.execute()
  ```
- Prefer `allkeys-lfu` over `allkeys-lru` when access patterns are highly skewed — LFU avoids
  evicting frequently used keys that happened not to be accessed recently.
- Monitor hit rate: `INFO stats` → `keyspace_hits` / (`keyspace_hits` + `keyspace_misses`).
  Target > 90% for effective caching; below 80% indicates TTL too short or cache too small.

## Security

- Cache-only Redis nodes still require authentication — `requirepass` or ACL.
- Never cache secrets (passwords, private keys, API tokens) in shared Redis instances.
- Use separate Redis databases or instances for different sensitivity tiers (session vs content cache).
- Set appropriate `maxmemory` to prevent cache exhaustion DoS.
- Bind to private network interface only; never expose port 6379 to the public internet.

## Testing

Test TTL behavior without sleeping — use `miniredis` (Go) or `fakeredis` (Python) time advancement:
```go
mr, _ := miniredis.Run()
client := redis.NewClient(&redis.Options{Addr: mr.Addr()})
mr.FastForward(5 * time.Minute)   // simulate TTL expiry without sleeping
```

Test stampede prevention with concurrent goroutines/threads hitting a cold cache simultaneously.
Verify that exactly one DB call is made for N concurrent requests on a cold key.

## Dos
- Set TTLs on every cache key — use `SET key value EX seconds` or `SETEX`, never bare `SET`.
- Use `allkeys-lru` or `allkeys-lfu` eviction on cache-only nodes so Redis can self-manage memory.
- Prefix keys with service name to prevent collisions in shared clusters.
- Monitor hit rate and eviction rate via `INFO stats`; alert when hit rate drops below threshold.
- Use probabilistic early expiration or mutex locking to prevent stampedes on expensive keys.
- Disable persistence (`save ""`, `appendonly no`) on cache-only nodes — it wastes disk and CPU.

## Don'ts
- Don't use Redis cache as a source of truth — always be able to reconstruct from the origin store.
- Don't set TTLs longer than data freshness requirements allow — stale cache is worse than no cache.
- Don't cache user-specific data in a shared key without the user ID in the key name.
- Don't store large values (> 100 KB) without understanding the impact on memory and serialization.
- Don't use `KEYS *` in production code for cache inspection — use `SCAN` with a cursor.
- Don't share a cache Redis instance with a primary-store Redis instance without namespace isolation.
