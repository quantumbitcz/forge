# SQLDelight Best Practices

## Overview
SQLDelight generates type-safe Kotlin APIs from `.sq` SQL files, with full Kotlin Multiplatform (KMP) support, coroutine/Flow integration, and compile-time SQL validation. Use it for KMP projects sharing persistence logic across Android, iOS, and JVM, or for any Kotlin project preferring hand-written SQL over an ORM abstraction. Avoid it if your team is more productive with higher-level ORMs or if you need dynamic/runtime query construction.

## Architecture Patterns

### SQL File Design (.sq files)
```sql
-- src/commonMain/sqldelight/com/example/Order.sq

CREATE TABLE orders (
  id         INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  total      REAL    NOT NULL,
  status     TEXT    NOT NULL DEFAULT 'pending',
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX orders_user_idx ON orders(user_id);
CREATE INDEX orders_status_idx ON orders(status, created_at);

findById:
SELECT *
FROM orders
WHERE id = :id;

findByUserId:
SELECT *
FROM orders
WHERE user_id = :userId
ORDER BY created_at DESC;

findByStatus:
SELECT o.*, u.email AS user_email
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.status = :status
LIMIT :limit;

insert:
INSERT INTO orders (user_id, total, status)
VALUES (:userId, :total, :status);

updateStatus:
UPDATE orders
SET status = :status
WHERE id = :id;

deleteByUserId:
DELETE FROM orders WHERE user_id = :userId;

countByStatus:
SELECT status, COUNT(*) AS count
FROM orders
GROUP BY status;
```

### Generated Kotlin API Usage
```kotlin
// SQLDelight generates: OrdersQueries with type-safe methods
class OrderRepository(private val queries: OrdersQueries) {

    fun findById(id: Long): Order? =
        queries.findById(id).executeAsOneOrNull()

    fun findByUserId(userId: Long): List<Order> =
        queries.findByUserId(userId).executeAsList()

    // Flow: re-emits on every data change touching the orders table
    fun observeByUserId(userId: Long): Flow<List<Order>> =
        queries.findByUserId(userId).asFlow().mapToList(Dispatchers.IO)

    suspend fun insert(userId: Long, total: Double): Long =
        withContext(Dispatchers.IO) {
            queries.insert(userId, total, "pending")
            queries.selectLastInsertedRowId().executeAsOne()
        }

    suspend fun updateStatus(id: Long, status: String) =
        withContext(Dispatchers.IO) {
            queries.updateStatus(status, id)
        }
}
```

### Custom Types
```kotlin
// schema.sq — define custom column type adapters
CREATE TABLE events (
  id         INTEGER NOT NULL PRIMARY KEY,
  type       TEXT    NOT NULL,   -- maps to EventType enum
  occurred_at TEXT   NOT NULL    -- maps to Instant
);

// In Kotlin — provide column adapters
val eventAdapter = Events.Adapter(
    typeAdapter       = EnumColumnAdapter(EventType::class),
    occurred_atAdapter = object : ColumnAdapter<Instant, String> {
        override fun decode(databaseValue: String) = Instant.parse(databaseValue)
        override fun encode(value: Instant)        = value.toString()
    }
)

val database = AppDatabase(driver, Events.Adapter(typeAdapter, occurred_atAdapter))
```

### Multiplatform Driver Setup
```kotlin
// commonMain: interface
expect fun createDriver(schema: SqlSchema<QueryResult.AsyncValue<Unit>>): SqlDriver

// androidMain
actual fun createDriver(schema: SqlSchema<QueryResult.AsyncValue<Unit>>): SqlDriver =
    AndroidSqliteDriver(schema, context, "app.db")

// iosMain
actual fun createDriver(schema: SqlSchema<QueryResult.AsyncValue<Unit>>): SqlDriver =
    NativeSqliteDriver(schema, "app.db")

// jvmMain (tests / desktop)
actual fun createDriver(schema: SqlSchema<QueryResult.AsyncValue<Unit>>): SqlDriver =
    JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY).also { schema.create(it) }
```

## Configuration

```kotlin
// build.gradle.kts
sqldelight {
    databases {
        create("AppDatabase") {
            packageName.set("com.example.db")
            srcDirs.setFrom("src/commonMain/sqldelight")
            deriveSchemaFromMigrations.set(true)  // derive schema from .sqm migration files
            verifyMigrations.set(true)             // fail build if migrations are inconsistent
        }
    }
}
```

## Performance

### Coroutine and Flow Support
```kotlin
// asFlow() wraps queries in SQLDelight's QueryResult.Flow
// mapToList / mapToOne are extension functions from sqldelight-coroutines-extensions
val ordersFlow: Flow<List<Order>> = queries
    .findByUserId(userId)
    .asFlow()
    .mapToList(Dispatchers.IO)

// Use distinctUntilChanged() to avoid recomposition when data is unchanged
val orders by viewModel.orders
    .distinctUntilChanged()
    .collectAsStateWithLifecycle()
```

### Transactions for Batch Operations
```kotlin
// SQLDelight transactions: wrap many statements in one commit
suspend fun syncOrders(remote: List<RemoteOrder>) = withContext(Dispatchers.IO) {
    database.transaction {
        queries.deleteByUserId(remote.first().userId)
        remote.forEach { o ->
            queries.insert(o.userId, o.total, o.status)
        }
    }
}
```

### Migration Verification
```sql
-- src/commonMain/sqldelight/migrations/2.sqm
ALTER TABLE orders ADD COLUMN notes TEXT;
CREATE INDEX orders_notes_idx ON orders(notes) WHERE notes IS NOT NULL;
```

```kotlin
// verifyMigrations = true in Gradle causes build failure if migration SQL
// doesn't match the expected schema — catches errors before runtime
```

## Security

```sql
-- SQLDelight always generates parameterized queries for :named bindings
-- All values passed to generated methods are bound parameters — no injection

-- SAFE: user input via named parameter
findByEmail:
SELECT * FROM users WHERE email = :email;

-- The generated Kotlin: findByEmail(email: String) — binding is automatic
```

```kotlin
// Encrypted SQLite with SQLCipher
val driver = AndroidSqliteDriver(
    schema    = AppDatabase.Schema,
    context   = context,
    name      = "app.db",
    factory   = SupportFactory("passphrase".toByteArray())  // SQLCipher
)
```

## Testing

```kotlin
// Use JdbcSqliteDriver with IN_MEMORY for fast unit tests
class OrderRepositoryTest {
    private lateinit var db:      AppDatabase
    private lateinit var queries: OrdersQueries

    @Before fun setup() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        db      = AppDatabase(driver)
        queries = db.ordersQueries
    }

    @Test fun `insert and findById round-trip`() {
        queries.insert(userId = 1L, total = 49.99, status = "pending")
        val id    = queries.selectLastInsertedRowId().executeAsOne()
        val order = queries.findById(id).executeAsOneOrNull()
        assertNotNull(order)
        assertEquals(49.99, order!!.total, 0.001)
    }

    @Test fun `observeByUserId emits on insert`() = runTest {
        val flow = queries.findByUserId(1L).asFlow().mapToList(Dispatchers.Unconfined)
        flow.test {
            assertEquals(0, awaitItem().size)
            queries.insert(1L, 10.0, "pending")
            assertEquals(1, awaitItem().size)
            cancelAndIgnoreRemainingEvents()
        }
    }
}
```

## Dos
- Write SQL in `.sq` files — SQLDelight validates syntax and column types at compile time.
- Use `deriveSchemaFromMigrations = true` and `.sqm` migration files for production schema management.
- Set `verifyMigrations = true` — the build fails if migration files are inconsistent with the schema.
- Use `database.transaction { }` for batch inserts/deletes to reduce lock contention and improve throughput.
- Use `asFlow().mapToList()` for UI observation — Flow re-emits automatically when the table changes.
- Use custom `ColumnAdapter` for domain types (Instant, UUID, enums) instead of raw primitives.
- Name queries descriptively (`findByUserId`, `updateStatus`) — the generated API mirrors these names.

## Don'ts
- Don't write queries in Kotlin string templates — put all SQL in `.sq` files for compile-time validation.
- Don't perform database operations on the main thread — always use `Dispatchers.IO`.
- Don't use `executeAsOne()` when the result might be null — use `executeAsOneOrNull()` to avoid exceptions.
- Don't skip migration verification in CI — `verifyMigrations = true` is the safest default.
- Don't store sensitive data unencrypted on device — use SQLCipher or Android's EncryptedFile for at-rest encryption.
- Don't rely on SQLite's weak typing for schema correctness — be explicit with `NOT NULL` and type affinity.
- Don't use `executeAsList()` on unbounded queries in UI code — always add `LIMIT` to prevent memory issues.
