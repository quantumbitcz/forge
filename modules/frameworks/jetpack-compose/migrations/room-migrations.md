# Room Migrations with Jetpack Compose

## Integration Setup

```kotlin
// Ensure exportSchema = true in @Database annotation
@Database(entities = [...], version = 3, exportSchema = true)
abstract class AppDatabase : RoomDatabase()

// Add migrations to Room builder
Room.databaseBuilder(ctx, AppDatabase::class.java, "app.db")
    .addMigrations(MIGRATION_1_2, MIGRATION_2_3)
    .build()
```

## Framework-Specific Patterns

### Manual Migration
```kotlin
val MIGRATION_1_2 = object : Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE todos ADD COLUMN notes TEXT")
    }
}

val MIGRATION_2_3 = object : Migration(2, 3) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE orders_new (
                id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                user_id INTEGER NOT NULL,
                total REAL NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending'
            )
        """)
        db.execSQL("INSERT INTO orders_new SELECT id, user_id, total, 'pending' FROM orders")
        db.execSQL("DROP TABLE orders")
        db.execSQL("ALTER TABLE orders_new RENAME TO orders")
    }
}
```

### Auto-Migrations (Room 2.4+)
```kotlin
@Database(
    entities = [TodoEntity::class],
    version  = 4,
    exportSchema = true,
    autoMigrations = [
        AutoMigration(from = 3, to = 4),                               // simple additive change
        AutoMigration(from = 2, to = 3, spec = Migration2To3Spec::class) // with spec for renames
    ]
)
abstract class AppDatabase : RoomDatabase()

@RenameColumn(tableName = "todos", fromColumnName = "description", toColumnName = "notes")
class Migration2To3Spec : AutoMigrationSpec
```

### Migration Testing
```kotlin
@RunWith(AndroidJUnit4::class)
class MigrationTest {
    private val TEST_DB = "migration-test"

    @get:Rule val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(), AppDatabase::class.java
    )

    @Test fun migrate1To2() {
        helper.createDatabase(TEST_DB, 1).apply {
            execSQL("INSERT INTO todos VALUES (1, 'old todo', 0)")
            close()
        }
        helper.runMigrationsAndValidate(TEST_DB, 2, true, MIGRATION_1_2).apply {
            val cursor = query("SELECT notes FROM todos WHERE id = 1")
            assertTrue(cursor.moveToFirst())
            assertNull(cursor.getString(0))   // new nullable column
            close()
        }
    }
}
```

## Scaffolder Patterns

```yaml
patterns:
  migration: "data/local/migration/Migration{FromVersion}To{ToVersion}.kt"
  test:      "androidTest/data/local/MigrationTest.kt"
```

## Additional Dos/Don'ts

- DO use `AutoMigration` for simple additive changes (add column, add table)
- DO write `MigrationTestHelper` tests for every manual migration before shipping
- DO keep exported schema JSONs in version control alongside migrations
- DO prefer creating a new table + copying data over `ALTER TABLE` for structural changes
- DON'T use `fallbackToDestructiveMigration()` in production; data loss is unacceptable
- DON'T rename columns without `@RenameColumn` spec in `AutoMigration` — Room won't infer it
- DON'T skip version numbers — Room requires sequential version increments
