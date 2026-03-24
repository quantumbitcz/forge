# Room as Local Cache with Jetpack Compose

## Integration Setup

```kotlin
// Requires Room with Flow support (already in databases/sqlite.md)
implementation("androidx.room:room-ktx:2.6.1")
```

## Framework-Specific Patterns

### Cache-First Repository Pattern
```kotlin
class TodoRepository @Inject constructor(
    private val dao:    TodoDao,
    private val api:    TodoApi,
    private val clock:  Clock = Clock.systemUTC()
) {
    fun getTodos(): Flow<List<Todo>> = dao.observeAll()
        .onStart { refreshIfStale() }
        .map { it.map(TodoEntity::toDomain) }

    private suspend fun refreshIfStale() {
        val latest = dao.getLatestUpdatedAt() ?: return refresh()
        val ageMs   = clock.millis() - latest
        if (ageMs > TTL_MS) refresh()
    }

    private suspend fun refresh() {
        val remote = api.getTodos()
        dao.upsertAll(remote.map(TodoDto::toEntity))
    }

    companion object { private const val TTL_MS = 5 * 60 * 1_000L }  // 5 min TTL
}
```

### Upsert with OnConflict.REPLACE
```kotlin
@Dao
interface TodoDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(todos: List<TodoEntity>)

    @Query("SELECT * FROM todos ORDER BY updated_at DESC")
    fun observeAll(): Flow<List<TodoEntity>>

    // TTL support — timestamp column on each entity
    @Query("SELECT MAX(cached_at) FROM todos")
    suspend fun getLatestUpdatedAt(): Long?

    @Query("DELETE FROM todos WHERE cached_at < :threshold")
    suspend fun evictStaleEntries(threshold: Long)
}
```

### Entity with TTL Timestamp
```kotlin
@Entity(tableName = "todos")
data class TodoEntity(
    @PrimaryKey val id:        Long,
    val title:                  String,
    val completed:              Boolean,
    @ColumnInfo(name = "cached_at")
    val cachedAt:               Long = System.currentTimeMillis()
)
```

### Periodic Cache Eviction (WorkManager)
```kotlin
class CacheEvictionWorker @AssistedInject constructor(
    @Assisted ctx: Context,
    @Assisted params: WorkerParameters,
    private val dao: TodoDao
) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        val threshold = System.currentTimeMillis() - (24 * 60 * 60 * 1_000L)
        dao.evictStaleEntries(threshold)
        return Result.success()
    }
}
```

## Scaffolder Patterns

```yaml
patterns:
  entity:     "data/local/entity/{Entity}Entity.kt"
  dao:        "data/local/dao/{Entity}Dao.kt"
  repository: "data/repository/{Feature}RepositoryImpl.kt"
  worker:     "data/worker/CacheEvictionWorker.kt"
```

## Additional Dos/Don'ts

- DO store `cached_at` (Unix ms) on every cacheable entity for TTL-based eviction
- DO use `OnConflictStrategy.REPLACE` for upsert semantics during remote sync
- DO observe cache via `Flow` in ViewModels so Compose re-renders on background refresh
- DO schedule periodic eviction with WorkManager; don't rely solely on TTL checks at read time
- DON'T treat Room cache as the source of truth — always reconcile with remote on stale detection
- DON'T call `refresh()` on every `Flow` collection — check TTL to avoid redundant network calls
- DON'T cache unbounded lists; add `LIMIT` to DAO queries for paginated caches
