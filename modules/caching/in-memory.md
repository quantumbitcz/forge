# In-Memory Caching Best Practices

## Overview
Application-level in-memory caching using language-native data structures (maps, LRU caches) without external dependencies like Redis or Memcached. Suitable for single-instance apps, mobile/desktop clients, and KMP shared modules where external cache infrastructure is unavailable or unnecessary.

## Architecture Patterns
- **LRU cache**: fixed-size cache that evicts least-recently-used entries. Most common for bounded memory usage.
- **TTL-based expiration**: entries expire after a time-to-live, forcing re-fetch.
- **Stale-while-revalidate**: serve stale data immediately while refreshing in the background.

```kotlin
// Kotlin/KMP example
class InMemoryCache<K, V>(
    private val maxSize: Int = 100,
    private val ttlMs: Long = 5 * 60 * 1000
) {
    private data class Entry<V>(val value: V, val cachedAt: Long)
    private val store = LinkedHashMap<K, Entry<V>>(maxSize, 0.75f, true)

    fun get(key: K): V? {
        val entry = store[key] ?: return null
        if (System.currentTimeMillis() - entry.cachedAt > ttlMs) {
            store.remove(key)
            return null
        }
        return entry.value
    }

    fun put(key: K, value: V) {
        if (store.size >= maxSize) {
            store.remove(store.keys.first())
        }
        store[key] = Entry(value, System.currentTimeMillis())
    }

    fun invalidate(key: K) = store.remove(key)
    fun clear() = store.clear()
}
```

## Configuration
- Size the cache based on expected cardinality and entry size. Monitor heap usage.
- Choose TTL per use case: short (30s) for frequently changing data, long (1hr) for semi-static config.
- For KMP: use `expect/actual` to leverage platform-optimized cache implementations (NSCache on iOS, LruCache on Android).

## Performance
- In-memory caches are O(1) read/write — orders of magnitude faster than network or disk.
- Beware unbounded growth: always set `maxSize` or use weak references.
- For concurrent access: use `ConcurrentHashMap` (JVM), `Mutex` (coroutines), or platform atomics.

## Security
- In-memory caches are process-local — no network exposure risk.
- Clear caches containing user data on logout.
- On mobile: caches survive backgrounding but not process death. Do not rely on them for persistence.

## Testing
- Test eviction behavior with controlled clock (inject time source).
- Test concurrent access under contention.
- Test cache miss → fetch → cache put → cache hit flow.

## Dos
- Always bound cache size — unbounded maps cause OOM.
- Use thread-safe structures for shared caches.
- Instrument hit/miss ratio to tune size and TTL.
- Prefer this over external cache for single-process apps with low cardinality data.

## Don'ts
- Don't use in-memory cache as a shared state between instances — it is process-local only.
- Don't cache mutable objects without copying — callers may modify cached references.
- Don't assume cache survives process restart — always handle cold starts.
- Don't skip TTL — stale data without expiration is a bug.
