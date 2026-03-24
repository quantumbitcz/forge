# Room Migrations — Generic Patterns

## Overview

Android Room tracks database schema versions in an integer `version` field on the `@Database` annotation. Migrations are `Migration(from, to)` objects added to the `RoomDatabase.Builder`. Room 2.4+ adds `AutoMigration` for simple additive changes. Always export the schema JSON (`exportSchema = true`) and commit it for migration regression testing.

## Core Patterns

### Manual Migration
```kotlin
val MIGRATION_2_3 = object : Migration(2, 3) {
    override fun migrate(db: SupportSQLiteDatabase) {
        // Additive: add column
        db.execSQL("ALTER TABLE todos ADD COLUMN notes TEXT")
        // Structural: recreate table (SQLite ALTER TABLE is limited)
        db.execSQL("CREATE TABLE orders_new (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, total REAL NOT NULL)")
        db.execSQL("INSERT INTO orders_new SELECT id, user_id, total FROM orders")
        db.execSQL("DROP TABLE orders")
        db.execSQL("ALTER TABLE orders_new RENAME TO orders")
    }
}
```

### AutoMigration (Room 2.4+)
```kotlin
@Database(
    entities = [TodoEntity::class],
    version  = 4,
    exportSchema = true,
    autoMigrations = [
        AutoMigration(from = 3, to = 4),
        AutoMigration(from = 2, to = 3, spec = Migration2To3Spec::class)
    ]
)
abstract class AppDatabase : RoomDatabase()

@RenameColumn(tableName = "todos", fromColumnName = "desc", toColumnName = "notes")
class Migration2To3Spec : AutoMigrationSpec
```

### Migration Testing
```kotlin
@get:Rule val helper = MigrationTestHelper(
    InstrumentationRegistry.getInstrumentation(), AppDatabase::class.java
)

@Test fun migrate2To3() {
    helper.createDatabase(TEST_DB, 2).close()
    helper.runMigrationsAndValidate(TEST_DB, 3, true, MIGRATION_2_3)
}
```

## Dos
- Use `AutoMigration` for additive changes (add column, add table, rename column)
- Write `MigrationTestHelper` tests for every manual migration
- Commit exported schema JSONs alongside migration code
- Prefer new table + INSERT SELECT + DROP over multi-step ALTER TABLE

## Don'ts
- Don't use `fallbackToDestructiveMigration()` in production — data loss is permanent
- Don't skip version numbers — Room requires sequential version increments
- Don't use `AutoMigration` for destructive changes (drop column) — write a manual migration
