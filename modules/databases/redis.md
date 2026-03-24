# Redis Best Practices (Primary Data Store)

## Overview
This file covers Redis as a **primary data store** — persisted, durably configured, and treated as the source of truth. This is distinct from using Redis as a cache (see `modules/caching/redis.md`). Use Redis as a primary store for leaderboards, session stores with durability requirements, rate-limit counters, real-time pub/sub event streams, geospatial indexes, and job queues. Avoid Redis as a primary store for relational data, large documents (> a few KB per key), or workloads requiring complex ad-hoc queries.

## Architecture Patterns

**Choose the right data structure for the access pattern:**
```
Strings    → counters, serialized blobs, locks (SET key val EX 30 NX)
Hashes     → user profiles, settings objects (HSET user:42 name "Alice" plan "pro")
Sets       → unique membership, tags (SADD user:42:tags "premium" "beta")
Sorted Sets → leaderboards, priority queues (ZADD scores 1500.0 "user:42")
Streams    → append-only event logs, job queues (XADD events * type "purchase")
Lists      → FIFO queues (LPUSH / BRPOP), activity feeds (bounded with LTRIM)
```

**Streams for durable job queues (prefer over Lists for reliability):**
```bash
# Producer
XADD jobs * type email payload '{"to":"alice@example.com"}'
# Consumer group (at-least-once delivery with ACK)
XGROUP CREATE jobs workers $ MKSTREAM
XREADGROUP GROUP workers w1 COUNT 10 BLOCK 2000 STREAMS jobs >
XACK jobs workers <message-id>   # after successful processing
```
Streams persist messages and support consumer groups — a crashed worker does not lose its in-flight message.

**Sorted Set for leaderboard with rank lookup:**
```bash
ZADD leaderboard:weekly 9850 "user:101"
ZREVRANK leaderboard:weekly "user:101"   # → 0 (rank 1)
ZREVRANGE leaderboard:weekly 0 9 WITHSCORES  # top 10
```

**Atomic operations with Lua scripts for compound operations:**
```lua
-- Decrement only if > 0 (rate limit token bucket)
local current = redis.call('GET', KEYS[1])
if current and tonumber(current) > 0 then
  return redis.call('DECRBY', KEYS[1], ARGV[1])
end
return 0
```

**Anti-pattern — storing large JSON blobs as plain Strings:** A 50 KB JSON blob in a String key loads the entire value for any field access. Use a Hash for structured objects (field-level reads/writes), or break large documents into smaller keys.

## Configuration

**Persistence (production — RDB + AOF hybrid):**
```conf
# RDB snapshots (point-in-time backup)
save 3600 1       # after 1 hour if >= 1 change
save 300 100      # after 5 min if >= 100 changes
save 60 10000     # after 1 min if >= 10000 changes

# AOF (append-only file — durability per write)
appendonly yes
appendfsync everysec   # balance: at most 1 second of data loss
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
```

**Memory management:**
```conf
maxmemory 4gb
maxmemory-policy allkeys-lru    # for caching layers within the store
# For primary store data that must not be evicted:
maxmemory-policy noeviction     # returns error when full instead of evicting
```

**Eviction policies for primary store:** Use `noeviction` when all keys are authoritative. Use `volatile-lru` only for keys with explicit TTLs (session tokens, rate limit windows).

**Connection (application):**
```python
import redis
r = redis.Redis(host="redis", port=6379, db=0,
                decode_responses=True,
                socket_connect_timeout=2,
                retry_on_timeout=True)
```

## Performance

**Pipeline commands to reduce round-trips:**
```python
pipe = r.pipeline()
for user_id in user_ids:
    pipe.hget(f"user:{user_id}", "plan")
results = pipe.execute()  # single round-trip for all commands
```

**Avoid `KEYS *` in production** — it blocks the event loop for the duration of the scan. Use `SCAN` with a cursor instead:
```bash
SCAN 0 MATCH user:* COUNT 100
```

**Monitor memory per data structure:** `MEMORY USAGE key` reports exact bytes. `OBJECT ENCODING key` shows whether Redis is using a compact (ziplist/listpack) or full encoding — small collections use compact encodings automatically.

**Avoid large sorted sets with `ZRANGE` returning millions of members** — paginate with `ZRANGE key min max BYSCORE LIMIT offset count`.

**Slow log for identifying blocking commands:**
```bash
CONFIG SET slowlog-log-slower-than 10000   # microseconds
SLOWLOG GET 25
```

## Security

**Require authentication (Redis 6+ ACL):**
```conf
aclfile /etc/redis/users.acl
```
```
# users.acl
user app on >secretpassword ~* &* +@all -DEBUG -CONFIG -SHUTDOWN
user readonly on >readpass ~* &* +@read
```

**Never expose Redis port (6379) to the internet** — Redis has no query parsing safety net. Bind to localhost or a private network interface:
```conf
bind 127.0.0.1 10.0.0.5
protected-mode yes
```

**TLS for production (Redis 6+):**
```conf
tls-port 6380
tls-cert-file /etc/ssl/redis.crt
tls-key-file /etc/ssl/redis.key
tls-ca-cert-file /etc/ssl/ca.crt
```

**Rename or disable dangerous commands:**
```conf
rename-command FLUSHALL ""
rename-command DEBUG ""
rename-command CONFIG ""
```

## Testing

Use **Testcontainers** for integration tests:
```java
@Container
static GenericContainer<?> redis = new GenericContainer<>("redis:7.2-alpine")
    .withExposedPorts(6379)
    .withCommand("redis-server", "--appendonly", "yes");
```

For unit tests of logic that calls Redis, use `fakeredis` (Python) or `miniredis` (Go) for in-process simulation without Docker:
```go
mr, _ := miniredis.Run()
client := redis.NewClient(&redis.Options{Addr: mr.Addr()})
```
Always test TTL expiration behavior (advance time in miniredis/fakeredis rather than sleeping).

## Dos
- Choose the data structure that matches the access pattern — Sorted Sets for rankings, Streams for queues, Hashes for objects.
- Enable AOF persistence (`appendonly yes`) for primary store durability; use RDB snapshots for backup.
- Use consumer groups with `XREADGROUP` for reliable job queues — they survive worker crashes.
- Set `maxmemory` and an explicit `maxmemory-policy` — without it Redis silently consumes all available RAM.
- Pipeline multi-key reads/writes to reduce network round-trips.
- Use `SCAN` with `MATCH` and `COUNT` instead of `KEYS *` for key enumeration.
- Set meaningful TTLs on ephemeral keys (sessions, OTPs, rate limit windows) using `EXPIRE` or `SET ... EX`.

## Don'ts
- Don't run Redis without `requirepass` / ACL in any network-accessible environment — default Redis has no authentication.
- Don't use `FLUSHDB` / `FLUSHALL` in production scripts — there is no undo; disable with `rename-command`.
- Don't store large objects (> ~10 KB) in Strings when only a subset of fields is accessed — use Hashes or a separate KV key per field.
- Don't use `KEYS *` in production code — it is O(N) and blocks all other commands.
- Don't use `MULTI/EXEC` transactions as a substitute for Lua scripts when you need read-modify-write atomicity — between `MULTI` and `EXEC` another client can modify the watched key; use `EVAL` with Lua for true atomicity.
- Don't set `appendfsync always` unless you need write-level durability — it creates a disk fsync per command and severely limits throughput.
- Don't use Redis Pub/Sub for reliable messaging — messages are lost if no subscriber is connected at delivery time; use Streams instead.
