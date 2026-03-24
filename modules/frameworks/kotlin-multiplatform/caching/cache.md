# Caching with Kotlin Multiplatform

## Integration Setup

```kotlin
// No extra dependency for in-memory caching (uses coroutines)
// SQLDelight for persistent cache (see databases/sqlite.md)
commonMain.dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
    implementation("app.cash.sqldelight:coroutines-extensions:2.0.2")
}
```

## Framework-Specific Patterns

### In-Memory Cache (StateFlow-based)
```kotlin
class InMemoryCache<K, V>(private val ttlMs: Long = 5 * 60_000L) {
    private data class Entry<V>(val value: V, val expiresAt: Long)
    private val store = MutableStateFlow<Map<K, Entry<V>>>(emptyMap())

    fun get(key: K): V? {
        val entry = store.value[key] ?: return null
        return if (Clock.System.now().toEpochMilliseconds() < entry.expiresAt) entry.value else null
    }

    fun set(key: K, value: V) {
        store.update { it + (key to Entry(value, Clock.System.now().toEpochMilliseconds() + ttlMs)) }
    }

    fun invalidate(key: K) { store.update { it - key } }
    fun clear() { store.value = emptyMap() }
}
```

### SQLDelight as Persistent Cache
```kotlin
class TodoCache(private val queries: TodoCacheQueries, private val ttlMs: Long = 10 * 60_000L) {
    suspend fun get(id: Long): Todo? {
        val row = queries.selectById(id).executeAsOneOrNull() ?: return null
        return if (Clock.System.now().toEpochMilliseconds() < row.cached_at + ttlMs)
            row.toDomain() else null.also { queries.deleteById(id) }
    }

    suspend fun set(todo: Todo) {
        queries.upsert(todo.id, todo.title, todo.completed,
                       Clock.System.now().toEpochMilliseconds())
    }
}
```

### expect/actual for Platform Cache
```kotlin
// commonMain — platform cache for large objects (images, binary data)
expect class PlatformCache {
    fun get(key: String): ByteArray?
    fun set(key: String, value: ByteArray, ttlSeconds: Int)
    fun remove(key: String)
}

// androidMain
actual class PlatformCache : AndroidPlatformCache()   // DiskLruCache-backed

// iosMain
actual class PlatformCache : IosPlatformCache()       // NSCache-backed
```

### Koin Wiring
```kotlin
val cacheModule = module {
    single { InMemoryCache<Long, Todo>(ttlMs = 5 * 60_000L) }
    single { TodoCache(get(), ttlMs = 10 * 60_000L) }
    single { PlatformCache() }
}
```

## Scaffolder Patterns

```yaml
patterns:
  in_memory_cache: "commonMain/kotlin/.../cache/InMemoryCache.kt"
  platform_cache:  "commonMain/kotlin/.../cache/PlatformCache.kt"
  persistent_cache: "commonMain/kotlin/.../cache/{Entity}Cache.kt"
```

## Additional Dos/Don'ts

- DO use `InMemoryCache` for transient session data; use SQLDelight cache for data surviving app restart
- DO store `cached_at` timestamps and check TTL on every read — avoid stale data silently
- DO use `expect/actual` for platform-native caches (NSCache on iOS, DiskLruCache on Android)
- DO size in-memory caches conservatively; mobile memory limits are strict (especially iOS)
- DON'T use global singletons for cache without TTL — unbounded memory growth crashes apps
- DON'T cache authentication tokens in general-purpose caches — use `TokenStore` with encrypted storage
- DON'T share cache instances across tests; use fresh instances to avoid test pollution
