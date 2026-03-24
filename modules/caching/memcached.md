# Memcached — Caching Best Practices

## Overview

Memcached is a simple, high-performance, distributed memory cache. Use it for workloads that
need maximum throughput on simple key-value caching with predictable memory usage. Compared to
Redis, Memcached has no persistence, no replication, no pub/sub, and no complex data structures —
its simplicity is its strength for pure caching at scale. Choose Memcached when you need linear
horizontal scaling, multi-threaded performance, and strict memory caps without operational overhead.

## Architecture Patterns

### Consistent Hashing (Client-Side Sharding)
Memcached has no built-in clustering — the client is responsible for distributing keys across nodes.
Always use consistent hashing to minimize key remapping when nodes are added or removed:
```python
# pylibmc with consistent hashing (ketama)
import pylibmc
mc = pylibmc.Client(
    ["10.0.0.1:11211", "10.0.0.2:11211", "10.0.0.3:11211"],
    behaviors={"ketama": True, "tcp_nodelay": True, "no_block": True}
)
```
With consistent hashing, adding one node remaps ~1/N keys instead of all keys.

### Multi-Get Optimization (Batched Reads)
```python
# Instead of N individual gets:
keys = [f"user:{uid}" for uid in user_ids]
results = mc.get_multi(keys)   # single network round-trip for all keys
missing = [uid for uid, key in zip(user_ids, keys) if key not in results]
# Fetch missing from DB and populate cache
if missing:
    users = db.find_users(missing)
    mc.set_multi({f"user:{u.id}": serialize(u) for u in users}, time=300)
```
`get_multi` is the single most impactful Memcached optimization — batch all related key reads.

### CAS (Check-And-Set) for Atomic Updates
```python
# Read-modify-write without race condition
result = mc.gets(f"counter:{resource_id}")
if result:
    value, cas_token = result
    new_value = value + 1
    if not mc.cas(f"counter:{resource_id}", new_value, cas_token, time=60):
        # CAS failed — another writer updated the value; retry
        handle_conflict()
```
CAS prevents lost updates in concurrent modification scenarios without distributed locks.

### Cache-Aside Pattern
```python
def get_product(product_id: str) -> Product:
    key = f"product:{product_id}"
    cached = mc.get(key)
    if cached is not None:
        return deserialize(cached)
    product = db.find_product(product_id)
    mc.set(key, serialize(product), time=600)
    return product
```

### Namespace Versioning (Bulk Invalidation)
Memcached has no built-in namespace invalidation — use a version key:
```python
def get_namespace_version(ns: str) -> int:
    v = mc.get(f"ns:{ns}:ver")
    return int(v) if v else 1

def get_namespaced(ns: str, key: str):
    ver = get_namespace_version(ns)
    return mc.get(f"{ns}:v{ver}:{key}")

def invalidate_namespace(ns: str):
    mc.incr(f"ns:{ns}:ver", 1)   # all old keys become unreachable (GC'd by eviction)
```

## Configuration

**Slab allocation tuning:**
```bash
# Start memcached with tuned slab growth factor
memcached -m 4096 -f 1.25 -n 72

# -m: memory limit in MB
# -f: slab growth factor (default 1.25 — adjust to match value size distribution)
# -n: minimum value size in bytes (default 48)
```
Check slab efficiency with `stats slabs` and `stats items`. If one slab class is heavily used and
another is empty, tune `-f` to better match your value size distribution.

**Connection pooling (application side):**
```python
# spymemcached (Java) — shared connection pool
MemcachedClient mc = new MemcachedClient(
    new ConnectionFactoryBuilder()
        .setProtocol(ConnectionFactoryBuilder.Protocol.BINARY)
        .setOpTimeout(500)
        .setMaxReconnectDelay(30)
        .build(),
    AddrUtil.getAddresses("mc1:11211 mc2:11211")
);
```
Use binary protocol — it is more efficient and supports CAS, verbosity controls, and SASL auth.

## Performance

- `get_multi` / `set_multi` are the highest-impact optimizations — batch all key operations.
- Prefer short, fixed-length keys (< 250 bytes) to minimize key hashing overhead.
- Use binary protocol (not ASCII) for reduced parsing overhead and full feature access.
- Set `tcp_nodelay` on the client to disable Nagle's algorithm — reduces latency for small values.
- Monitor `evictions` stat: sustained evictions mean the cache is undersized for the working set.
- Monitor `get_hits` / `get_misses` ratio; below 80% indicates cache too small or TTLs too short.

## Security

- Enable SASL authentication (binary protocol required):
  ```bash
  memcached -S   # enable SASL; configure SASL credentials separately
  ```
- Bind to private network interface only — Memcached has no access control without SASL:
  ```bash
  memcached -l 10.0.0.5   # bind to internal IP only; never 0.0.0.0 in production
  ```
- Use a firewall/security group to restrict port 11211 to application servers only.
- Never store PII or secrets in Memcached without encryption at the application layer — data is
  stored in plaintext in memory and on the network without TLS.

## Testing

```python
# Use a real Memcached via Testcontainers for integration tests
from testcontainers.memcached import MemcachedContainer

with MemcachedContainer("memcached:1.6-alpine") as mc_container:
    client = pylibmc.Client([mc_container.get_client_url()])
    client.set("key", "value", time=60)
    assert client.get("key") == "value"
```

For unit tests, mock the cache client interface. Test CAS conflict paths by injecting a mock that
returns a failed CAS result on the first attempt.

## Dos
- Use consistent hashing (ketama) so node additions/removals only remap ~1/N keys.
- Batch all key reads with `get_multi` — it is a single round-trip regardless of key count.
- Monitor `evictions` and `curr_items` to detect undersized cache before hit rate drops.
- Use the binary protocol for efficiency, SASL support, and CAS operations.
- Tune slab allocation (`-f` growth factor) to match your actual value size distribution.

## Don'ts
- Don't rely on Memcached for data durability — it has no persistence; all data is lost on restart.
- Don't use ASCII protocol in production — binary protocol is faster and supports more features.
- Don't expose port 11211 to any untrusted network — Memcached has no built-in access control in ASCII mode.
- Don't store values larger than 1 MB (the default limit) — split large objects or use object storage.
- Don't implement fan-out invalidation with individual `delete` calls — use namespace versioning for bulk invalidation.
