# Room as Local Cache Best Practices

## Overview
Using Room (Android's SQLite abstraction) as a local cache layer for data fetched from remote APIs. Provides offline-first behavior, reactive UI updates via Flow/LiveData, and structured cache eviction. Use when your mobile app needs offline access or instant UI rendering from local data.

## Architecture Patterns
- **Cache-aside with TTL**: store API responses in Room with a `cachedAt` timestamp column. Check freshness before serving.
- **Single source of truth**: UI always reads from Room. Network fetches write to Room, which triggers reactive updates.
- **Repository pattern**: repository decides whether to serve from cache, fetch from network, or both (stale-while-revalidate).

```kotlin
@Entity
data class CachedUser(
    @PrimaryKey val id: String,
    val name: String,
    val email: String,
    val cachedAt: Long = System.currentTimeMillis()
)

@Dao
interface UserCacheDao {
    @Query("SELECT * FROM CachedUser WHERE id = :id AND cachedAt > :minTimestamp")
    fun getFresh(id: String, minTimestamp: Long): Flow<CachedUser?>

    @Upsert
    suspend fun upsert(user: CachedUser)

    @Query("DELETE FROM CachedUser WHERE cachedAt < :threshold")
    suspend fun evictStale(threshold: Long)
}
```

## Configuration
- Set `exportSchema = false` for cache-only databases (no migration history needed).
- Use a separate `RoomDatabase` instance for cache vs. primary user data.
- Configure `fallbackToDestructiveMigration()` — cache data is ephemeral.

## Performance
- Use `@Upsert` (Room 2.5+) instead of `@Insert(onConflict = REPLACE)` for fewer allocations.
- Batch eviction via `WorkManager` periodic task (not on every read).
- Index `cachedAt` column for fast eviction queries.

## Security
- Do not cache sensitive data (tokens, PII) in Room without encryption.
- Use `SQLCipher` if caching user-identifiable data.

## Testing
- Use in-memory Room database (`Room.inMemoryDatabaseBuilder()`) for unit tests.
- Test eviction logic with controlled timestamps.

## Dos
- Use `Flow` from DAO for reactive cache reads — UI updates automatically when cache is refreshed.
- Set reasonable TTL per entity type (user profiles: 5min, config: 1hr, static content: 24hr).
- Evict on logout or account switch.

## Don'ts
- Don't treat Room cache as permanent storage — always handle cache misses gracefully.
- Don't skip `fallbackToDestructiveMigration()` for cache databases — migration complexity is wasted on ephemeral data.
- Don't cache large binary data in Room — use file-based caching for images/videos.
