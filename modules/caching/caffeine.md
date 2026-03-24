# Caffeine — In-Process Cache Best Practices

## Overview

Caffeine is a high-performance, near-optimal in-process cache library for Java and Kotlin. Use it
for hot read paths where network latency to Redis/Memcached is unacceptable, for caching config or
reference data that changes rarely, and as an L1 cache in front of a distributed L2 cache. Because
the cache lives in the JVM heap, it is not shared across instances — cache-aside logic must tolerate
cold starts on new deployments and restart events.

## Architecture Patterns

### Loading Cache (Synchronous)
```java
LoadingCache<String, User> userCache = Caffeine.newBuilder()
    .maximumSize(10_000)
    .expireAfterWrite(Duration.ofMinutes(5))
    .recordStats()
    .build(userId -> userRepository.findById(userId));  // loader called on miss

User user = userCache.get("user-42");   // auto-loads on miss; never null (throws on loader failure)
```

### Async Loading Cache (Non-Blocking)
```java
AsyncLoadingCache<String, Product> productCache = Caffeine.newBuilder()
    .maximumSize(50_000)
    .expireAfterWrite(Duration.ofMinutes(10))
    .buildAsync(productId -> CompletableFuture.supplyAsync(
        () -> productRepository.findById(productId), executor));

CompletableFuture<Product> future = productCache.get("sku-99");
```
Async cache coalesces concurrent misses — multiple callers for the same key share a single in-flight
CompletableFuture, preventing stampedes without explicit locking.

### Manual Cache (Explicit Population)
```java
Cache<String, Report> reportCache = Caffeine.newBuilder()
    .maximumSize(1_000)
    .expireAfterAccess(Duration.ofHours(1))
    .build();

reportCache.put(reportId, report);
Report r = reportCache.getIfPresent(reportId);   // null on miss
Report r2 = reportCache.get(reportId, id -> reportService.generate(id));  // load-on-miss
```

### Refresh After Write (Stale-While-Revalidate)
```java
LoadingCache<String, Config> configCache = Caffeine.newBuilder()
    .maximumSize(100)
    .refreshAfterWrite(Duration.ofMinutes(1))  // async refresh — stale value returned during refresh
    .expireAfterWrite(Duration.ofMinutes(5))   // hard expiry safety net
    .build(configService::load);
```
`refreshAfterWrite` returns the stale entry immediately while asynchronously reloading — zero latency
for callers during refresh. Always pair with `expireAfterWrite` as a hard upper bound.

### Weight-Based Sizing
```java
Cache<String, byte[]> blobCache = Caffeine.newBuilder()
    .maximumWeight(100 * 1024 * 1024)   // 100 MB total weight
    .weigher((String key, byte[] val) -> val.length)
    .expireAfterWrite(Duration.ofMinutes(30))
    .build();
```
Use weight when entries have variable sizes. `maximumSize` counts entries; `maximumWeight` counts
logical units (bytes, rows). Do not combine both on the same cache.

### Eviction Listener
```java
Cache<String, Session> sessionCache = Caffeine.newBuilder()
    .maximumSize(5_000)
    .expireAfterWrite(Duration.ofMinutes(30))
    .evictionListener((String key, Session session, RemovalCause cause) -> {
        if (cause.wasEvicted()) {
            auditLog.record("session-evicted", key);
        }
    })
    .build();
```

## Configuration

**Sizing guidelines:**
- Start with `maximumSize` between 1 000 and 100 000 entries; tune based on `stats()`.
- Set `maximumSize` to the number of distinct keys expected in the hot working set, not total data.
- Use `recordStats()` in all environments; expose via Micrometer for production dashboards.

**Expiration strategy decision tree:**
```
Access pattern           → Recommendation
Read-heavy reference data  expireAfterWrite(duration) + refreshAfterWrite(shorter)
Session / per-request      expireAfterAccess(idle-timeout) + expireAfterWrite(absolute-max)
Expensive computations     expireAfterWrite(tolerance); refreshAfterWrite for low latency
Mutable data w/ push inval Manual invalidation (cache.invalidate(key)) + short expireAfterWrite
```

## Performance

- Caffeine uses a W-TinyLFU eviction policy — near-optimal hit rate, outperforms LRU for skewed access.
- Statistics overhead is minimal with `recordStats()` — always enable it; the hit rate data is essential.
- Use `AsyncLoadingCache` on I/O-bound loaders to avoid blocking the calling thread.
- Weak/soft references:
  - `weakKeys()` / `weakValues()`: entries are GC-eligible when not referenced elsewhere — useful for
    caches of large objects where GC pressure matters more than hit rate.
  - `softValues()`: GC clears entries only under memory pressure — good for image/report caches.
  - Avoid on frequently-accessed small entries — GC overhead exceeds cache benefit.

## Security

- Do not cache security-sensitive decisions (authorization results) with TTLs longer than the
  expected propagation time for permission revocations.
- Clear caches on logout or permission change: `cache.invalidate(userId)`.
- Never store raw credentials or private keys in a Caffeine cache — store derived tokens with short TTL.

## Testing

```java
// Inject the cache and manipulate it directly in tests
@Test
void returnsCachedUser() {
    userCache.put("u-1", testUser);
    User result = userService.getUser("u-1");
    verify(userRepository, never()).findById(any());  // loader not called
    assertEquals(testUser, result);
}

// Test eviction by using a ticker for time control
FakeTicker ticker = new FakeTicker();
Cache<String, String> cache = Caffeine.newBuilder()
    .expireAfterWrite(5, TimeUnit.MINUTES)
    .ticker(ticker::read)
    .build();
cache.put("k", "v");
ticker.advance(6, TimeUnit.MINUTES);
assertNull(cache.getIfPresent("k"));   // expired
```

## Dos
- Always call `recordStats()` and expose hit rate, eviction count, and load time via Micrometer.
- Use `AsyncLoadingCache` for I/O-bound loaders to prevent thread pool exhaustion on cache misses.
- Pair `refreshAfterWrite` with `expireAfterWrite` as a safety net for the stale-while-revalidate pattern.
- Size caches by the hot working set, not the total data volume.
- Invalidate explicitly on write mutations: `cache.invalidate(key)` or `cache.invalidateAll(keys)`.

## Don'ts
- Don't use `softValues()` as a substitute for sizing — rely on Caffeine's eviction, not GC.
- Don't share a single cache instance across unrelated domains — separate caches per entity type.
- Don't set `expireAfterWrite` to zero as a "no-cache" config — just don't use the cache at all.
- Don't mix `maximumSize` and `maximumWeight` on the same cache instance — they are mutually exclusive.
- Don't cache mutable objects without defensive copies — callers mutating a returned object corrupt the cache.
