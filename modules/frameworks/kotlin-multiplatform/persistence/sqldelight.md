# Kotlin Multiplatform + SQLDelight

> KMP-specific patterns for SQLDelight. Extends generic Kotlin Multiplatform conventions.
> Generic KMP patterns (expect/actual, shared modules, Koin DI) are NOT repeated here.

## Integration Setup

`build.gradle.kts` (shared module):
```kotlin
plugins {
    id("app.cash.sqldelight") version "2.0.2"
}

sqldelight {
    databases {
        create("AppDatabase") {
            packageName.set("com.example.db")
            schemaOutputDirectory.set(file("src/commonMain/sqldelight/databases"))
        }
    }
}

kotlin {
    sourceSets {
        commonMain.dependencies {
            implementation("app.cash.sqldelight:coroutines-extensions:2.0.2")
        }
        androidMain.dependencies {
            implementation("app.cash.sqldelight:android-driver:2.0.2")
        }
        iosMain.dependencies {
            implementation("app.cash.sqldelight:native-driver:2.0.2")
        }
        jvmMain.dependencies {
            implementation("app.cash.sqldelight:sqlite-driver:2.0.2")
        }
    }
}
```

## SQL Schema

```sql
-- shared/src/commonMain/sqldelight/com/example/db/Users.sq

CREATE TABLE users (
    id TEXT NOT NULL PRIMARY KEY,
    display_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);

-- Named queries (generate type-safe Kotlin functions)
selectAll:
SELECT * FROM users ORDER BY display_name ASC;

selectById:
SELECT * FROM users WHERE id = :id;

upsert:
INSERT OR REPLACE INTO users (id, display_name, email)
VALUES (:id, :display_name, :email);

deleteById:
DELETE FROM users WHERE id = :id;
```

SQLDelight generates `UsersQueries` with typed functions matching these names.

## expect/actual Drivers

```kotlin
// shared/src/commonMain/kotlin/db/DriverFactory.kt
expect class DriverFactory {
    fun createDriver(): SqlDriver
}

// shared/src/androidMain/kotlin/db/DriverFactory.kt
actual class DriverFactory(private val context: Context) {
    actual fun createDriver(): SqlDriver =
        AndroidSqliteDriver(AppDatabase.Schema, context, "app.db")
}

// shared/src/iosMain/kotlin/db/DriverFactory.kt
actual class DriverFactory {
    actual fun createDriver(): SqlDriver =
        NativeSqliteDriver(AppDatabase.Schema, "app.db")
}

// shared/src/jvmMain/kotlin/db/DriverFactory.kt (desktop / tests)
actual class DriverFactory {
    actual fun createDriver(): SqlDriver =
        JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY).also {
            AppDatabase.Schema.create(it)
        }
}
```

## Database Initialization

```kotlin
// shared/src/commonMain/kotlin/db/Database.kt
fun createAppDatabase(driverFactory: DriverFactory): AppDatabase {
    val driver = driverFactory.createDriver()
    // Run schema migrations before returning
    AppDatabase.Schema.migrate(driver, oldVersion = 0, newVersion = AppDatabase.Schema.version)
    return AppDatabase(driver)
}
```

## Flow Queries

```kotlin
// shared/src/commonMain/kotlin/repository/UserRepository.kt
import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import kotlinx.coroutines.Dispatchers

class UserRepository(private val db: AppDatabase) {
    fun observeUsers(): Flow<List<Users>> =
        db.usersQueries.selectAll()
            .asFlow()
            .mapToList(Dispatchers.Default)

    suspend fun upsert(user: User) = withContext(Dispatchers.Default) {
        db.usersQueries.upsert(user.id, user.displayName, user.email)
    }
}
```

## Schema Migrations

Version migrations are defined in `.sqm` files:

```
shared/src/commonMain/sqldelight/databases/
├── 1.sqm   ← initial schema (copied from .sq file)
├── 2.sqm   ← ALTER TABLE statements for version 2
```

`2.sqm`:
```sql
ALTER TABLE users ADD COLUMN avatar_url TEXT;
```

SQLDelight generates `migrate(driver, from, to)` that applies the correct `.sqm` files.

## Koin DI Wiring

```kotlin
// shared/src/commonMain/kotlin/di/DatabaseModule.kt
val databaseModule = module {
    single { createAppDatabase(get()) }
    single { get<AppDatabase>().usersQueries }
    single { UserRepository(get()) }
}
```

## Scaffolder Patterns

```yaml
patterns:
  sql_schema: "shared/src/commonMain/sqldelight/com/example/db/{Entity}.sq"
  driver_factory_common: "shared/src/commonMain/kotlin/db/DriverFactory.kt"
  driver_factory_android: "shared/src/androidMain/kotlin/db/DriverFactory.kt"
  driver_factory_ios: "shared/src/iosMain/kotlin/db/DriverFactory.kt"
  driver_factory_jvm: "shared/src/jvmMain/kotlin/db/DriverFactory.kt"
  repository: "shared/src/commonMain/kotlin/repository/{Entity}Repository.kt"
  migrations_dir: "shared/src/commonMain/sqldelight/databases/"
  di_module: "shared/src/commonMain/kotlin/di/DatabaseModule.kt"
```

## Additional Dos/Don'ts

- DO write named queries in `.sq` files — anonymous SQL loses type generation benefits
- DO use `asFlow().mapToList()` for reactive UI — it re-emits on every DB change
- DO use `IN_MEMORY` SQLite driver in unit tests (JVM actual) to avoid platform I/O
- DO commit generated schema JSON under `schemaOutputDirectory` for migration validation
- DON'T call SQLDelight queries on the main thread — dispatch to `Dispatchers.Default`
- DON'T skip `.sqm` files for version bumps — missing migrations cause runtime crashes on upgrade
- DON'T use `INSERT OR REPLACE` if you need to preserve row timestamps — it deletes and re-inserts
