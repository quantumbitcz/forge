# Django Migrations with Django

## Integration Setup

Django migrations are built-in (`django.db.migrations`). No additional dependencies for standard use.

```bash
# CI dependency for migration checks
# (uses built-in --check flag, no extra packages needed)
```

## Framework-Specific Patterns

### MIGRATION_MODULES Setting

```python
# settings.py
MIGRATION_MODULES = {
    "myapp": "myapp.db.migrations",   # Custom migration directory
    "thirdpartyapp": None,             # Disable migrations for this app (tests)
}
```

Use `None` in test settings for third-party apps to speed up `--keepdb` test runs.

### RunSQL for Raw SQL

```python
# migrations/0005_add_search_index.py
from django.db import migrations

class Migration(migrations.Migration):
    operations = [
        migrations.RunSQL(
            sql="CREATE INDEX CONCURRENTLY orders_search_idx ON orders USING GIN(search_vector)",
            reverse_sql="DROP INDEX IF EXISTS orders_search_idx",
            state_operations=[],      # No state change — pure DB operation
        ),
    ]
```

Wrap `CREATE INDEX CONCURRENTLY` in `atomic = False` on the migration class — concurrent index creation cannot run inside a transaction.

```python
class Migration(migrations.Migration):
    atomic = False
    operations = [
        migrations.RunSQL("CREATE INDEX CONCURRENTLY ..."),
    ]
```

### SeparateDatabaseAndState (Zero-Downtime)

```python
# migrations/0006_rename_status_column.py
class Migration(migrations.Migration):
    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunSQL(
                    "ALTER TABLE orders RENAME COLUMN status TO order_status",
                    reverse_sql="ALTER TABLE orders RENAME COLUMN order_status TO status",
                )
            ],
            state_operations=[
                migrations.RenameField("Order", "status", "order_status"),
            ],
        )
    ]
```

Use `SeparateDatabaseAndState` when the DB operation must be decoupled from Django's state model (e.g., column renames on live tables, backfills).

### Squashing Strategy

```bash
# Squash migrations 0001–0050 into a single optimized migration
python manage.py squashmigrations myapp 0001 0050

# After all environments have run the squashed migration:
# 1. Delete the original 0001–0050 files
# 2. Remove the replaces = [...] from the squash migration
```

Squash when an app accumulates 50+ migrations. Never squash across dependency boundaries with other apps.

### CI Check

```bash
# Verify no pending migrations were forgotten
python manage.py migrate --check
python manage.py makemigrations --check --dry-run
```

Add both checks to CI. `--check` exits non-zero if unapplied migrations exist.

## Scaffolder Patterns

```yaml
patterns:
  migrations_dir: "{app}/migrations/"
  initial_migration: "{app}/migrations/0001_initial.py"
  raw_sql_migration: "{app}/migrations/{NNNN}_{description}.py"
```

## Additional Dos/Don'ts

- DO set `atomic = False` on migrations containing `CREATE INDEX CONCURRENTLY` or `VACUUM`
- DO use `SeparateDatabaseAndState` for column renames and table splits — avoids lock-based downtime
- DO run `makemigrations --check` in CI to catch missing migrations before merge
- DON'T squash migrations that are still referenced by unapplied migrations in other environments
- DON'T use `RunPython` with inline lambdas — use module-level functions so Django can serialize them
- DON'T import models directly in `RunPython` operations — use `apps.get_model()` to get the historical version
