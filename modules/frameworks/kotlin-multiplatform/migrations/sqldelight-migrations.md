# SQLDelight Migrations with Kotlin Multiplatform

## Integration Setup

```kotlin
// build.gradle.kts (shared module)
sqldelight {
    databases {
        create("AppDatabase") {
            packageName.set("com.example.db")
            schemaOutputDirectory.set(file("src/commonMain/sqldelight/migrations"))
            migrationOutputFileFormat = ".sqm"
            verifyMigrations = true   // compile-time schema drift detection
        }
    }
}
```

## Framework-Specific Patterns

### Migration File Naming
SQLDelight uses numbered `.sqm` files. Files must be named sequentially:
```
src/commonMain/sqldelight/migrations/
  1.sqm    -- initial schema (auto-generated from .sq files at version 1)
  2.sqm    -- migration from version 1 → 2
  3.sqm    -- migration from version 2 → 3
```

### Migration File Content
```sql
-- 2.sqm — Add notes column to todos
ALTER TABLE Todo ADD COLUMN notes TEXT;

-- 3.sqm — Add index and new table
CREATE INDEX IF NOT EXISTS idx_todo_created ON Todo(created_at);

CREATE TABLE Tag (
    id    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    name  TEXT NOT NULL UNIQUE
);
```

### Schema Verification
```kotlin
// Run migrations against schema in tests
@Test fun migrationsAreValid() {
    val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
    AppDatabase.Schema.migrate(driver, 1, AppDatabase.Schema.version)
    // If migrations are out of sync with .sq files, this throws
}
```

### Driver Migration Invocation
```kotlin
// Apply migrations on first open
val driver = createDriver()
AppDatabase.Schema.migrate(
    driver = driver,
    oldVersion = currentVersion,   // read from stored user_version pragma
    newVersion = AppDatabase.Schema.version
)
val db = AppDatabase(driver)
```

## Scaffolder Patterns

```yaml
patterns:
  migration: "commonMain/sqldelight/migrations/{version}.sqm"
  schema_test: "commonTest/kotlin/.../db/MigrationTest.kt"
```

## Additional Dos/Don'ts

- DO enable `verifyMigrations = true` — catches schema drift at compile time
- DO store the current schema version and compare to `AppDatabase.Schema.version` at startup
- DO write migration tests that drive through every version increment
- DO keep `.sqm` files in version control alongside `.sq` schema files
- DON'T rename `.sqm` files after they've been shipped — version numbers are permanent
- DON'T delete old `.sqm` files; SQLDelight needs them to compute migration paths
- DON'T use `ALTER TABLE ... RENAME COLUMN` on SQLite < 3.25; use the copy-and-rename pattern
