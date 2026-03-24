# SQLite with Kotlin Multiplatform (SQLDelight)

## Integration Setup

```kotlin
// build.gradle.kts (root)
plugins { id("app.cash.sqldelight") version "2.0.2" }

// build.gradle.kts (shared module)
sqldelight {
    databases {
        create("AppDatabase") {
            packageName.set("com.example.db")
            generateAsync = true   // suspend + coroutine driver support
        }
    }
}

dependencies {
    // Drivers per platform
    androidMain.dependencies {
        implementation("app.cash.sqldelight:android-driver:2.0.2")
    }
    iosMain.dependencies {
        implementation("app.cash.sqldelight:native-driver:2.0.2")
    }
    jvmMain.dependencies {
        implementation("app.cash.sqldelight:sqlite-driver:2.0.2")
    }
    commonMain.dependencies {
        implementation("app.cash.sqldelight:coroutines-extensions:2.0.2")
    }
}
```

## Framework-Specific Patterns

### Schema Definition (.sq file)
```sql
-- commonMain/sqldelight/com/example/db/Todo.sq
CREATE TABLE Todo (
    id          INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    title       TEXT    NOT NULL,
    completed   INTEGER NOT NULL DEFAULT 0,     -- SQLite has no BOOLEAN
    created_at  INTEGER NOT NULL                -- Unix ms
);

selectAll:
SELECT * FROM Todo ORDER BY created_at DESC;

selectById:
SELECT * FROM Todo WHERE id = ?;

insert:
INSERT INTO Todo(title, completed, created_at) VALUES (?, ?, ?);

updateCompleted:
UPDATE Todo SET completed = ? WHERE id = ?;

deleteById:
DELETE FROM Todo WHERE id = ?;
```

### Platform-Specific Driver (expect/actual)
```kotlin
// commonMain
expect fun createDriver(schema: SqlSchema<QueryResult.AsyncValue<Unit>>): SqlDriver

// androidMain
actual fun createDriver(...) = AndroidSqliteDriver(schema, context, "app.db")

// iosMain
actual fun createDriver(...) = NativeSqliteDriver(schema, "app.db")

// jvmMain (tests)
actual fun createDriver(...) = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
    .also { schema.create(it).await() }
```

### Coroutine Flow Queries
```kotlin
val db = AppDatabase(driver)
val todos: Flow<List<Todo>> = db.todoQueries
    .selectAll()
    .asFlow()
    .mapToList(Dispatchers.Default)
```

## Scaffolder Patterns

```yaml
patterns:
  schema:     "commonMain/sqldelight/com/example/db/{Entity}.sq"
  driver:     "commonMain/kotlin/.../DatabaseDriverFactory.kt"
  repository: "commonMain/kotlin/.../repository/{Entity}RepositoryImpl.kt"
```

## Additional Dos/Don'ts

- DO use `generateAsync = true` to get suspend-compatible query functions
- DO define queries in `.sq` files — SQLDelight generates type-safe Kotlin at compile time
- DO use `asFlow().mapToList()` for reactive Compose / SwiftUI bindings
- DO use `expect/actual` for driver creation; keep all query logic in `commonMain`
- DON'T use raw SQL strings in Kotlin code; always write queries in `.sq` files
- DON'T share a single `SqlDriver` across coroutines without a connection pool on JVM
- DON'T use `INTEGER` 0/1 for booleans in ad-hoc queries — use SQLDelight's `BOOLEAN` adapter
