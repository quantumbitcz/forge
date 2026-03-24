# SQLDelight Migrations — Generic Patterns

## Overview

SQLDelight tracks schema versions with numbered `.sqm` migration files. The Gradle plugin generates `Schema.migrate(driver, from, to)` from these files. Enable `verifyMigrations = true` for compile-time drift detection. Migrations are pure SQL — no Kotlin DSL.

## Core Patterns

### Migration File Layout
```
src/commonMain/sqldelight/migrations/
  1.sqm    -- baseline (generated from initial .sq files)
  2.sqm    -- version 1 → 2
  3.sqm    -- version 2 → 3
```

### Migration File Content
```sql
-- 2.sqm — add column
ALTER TABLE Todo ADD COLUMN notes TEXT;

-- 3.sqm — add table and index
CREATE TABLE Tag (
    id    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    name  TEXT NOT NULL UNIQUE
);
CREATE INDEX idx_todo_created ON Todo(created_at);

-- 4.sqm — structural change (SQLite rename workaround)
ALTER TABLE Todo RENAME TO Todo_old;
CREATE TABLE Todo (
    id          INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    title       TEXT    NOT NULL,
    description TEXT,              -- renamed from notes
    completed   INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL
);
INSERT INTO Todo SELECT id, title, notes, completed, created_at FROM Todo_old;
DROP TABLE Todo_old;
```

### Gradle Configuration
```kotlin
sqldelight {
    databases {
        create("AppDatabase") {
            packageName.set("com.example.db")
            migrationOutputFileFormat = ".sqm"
            verifyMigrations = true     // fail build if .sqm files don't match .sq schema
        }
    }
}
```

### Migration Testing
```kotlin
@Test fun migrationsAreValid() {
    val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
    AppDatabase.Schema.migrate(driver, 1, AppDatabase.Schema.version)
    // Throws if any migration produces a schema that doesn't match .sq definitions
}
```

## Dos
- Enable `verifyMigrations = true` — catches schema drift at compile time
- Test full migration path in CI (`Schema.migrate(driver, 1, currentVersion)`)
- Keep `.sqm` files in version control alongside `.sq` files

## Don'ts
- Don't rename or delete shipped `.sqm` files — version numbers are permanent identifiers
- Don't use `ALTER TABLE ... RENAME COLUMN` on SQLite < 3.25 — use the copy-and-rename pattern
- Don't skip versions — SQLDelight expects a contiguous sequence of `.sqm` files
