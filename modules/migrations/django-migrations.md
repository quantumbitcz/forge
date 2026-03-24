# Django Migrations Best Practices

## Overview
Django's migration framework auto-detects schema changes from model definitions and generates migration files. Use it for any Django project with a relational database — it is the standard and built-in mechanism. Be cautious with `RunPython` data migrations on large tables in production; they run in a transaction and can lock tables.

## Architecture Patterns

### Directory structure
```
myapp/
└── migrations/
    ├── __init__.py
    ├── 0001_initial.py
    ├── 0002_add_user_bio.py
    ├── 0003_backfill_full_name.py   # data migration
    └── 0004_set_full_name_not_null.py
```

### Standard workflow
```bash
python manage.py makemigrations myapp --name add_user_bio
python manage.py migrate                  # applies all pending
python manage.py showmigrations           # list applied/pending
python manage.py sqlmigrate myapp 0002    # preview SQL
```

### Data migration with RunPython
```python
# 0003_backfill_full_name.py
from django.db import migrations

def backfill_full_name(apps, schema_editor):
    User = apps.get_model("myapp", "User")
    for user in User.objects.iterator(chunk_size=500):
        user.full_name = f"{user.first_name} {user.last_name}"
        user.save(update_fields=["full_name"])

def reverse_backfill(apps, schema_editor):
    User = apps.get_model("myapp", "User")
    User.objects.update(full_name=None)

class Migration(migrations.Migration):
    dependencies = [("myapp", "0002_add_user_bio")]
    operations = [
        migrations.RunPython(backfill_full_name, reverse_code=reverse_backfill),
    ]
```

### Always use `apps.get_model()` in RunPython
Never import model classes directly inside migration functions — use the historical model registry via `apps.get_model()` to avoid issues when models change later.

### Multi-step zero-downtime pattern
```python
# Migration 1: add nullable column
migrations.AddField(model_name="user", name="display_name",
                    field=models.CharField(max_length=255, null=True))

# Migration 2 (after code is deployed): RunPython backfill

# Migration 3: enforce NOT NULL constraint
migrations.AlterField(model_name="user", name="display_name",
                      field=models.CharField(max_length=255))
```

### Squashing old migrations
```bash
python manage.py squashmigrations myapp 0001 0020 --squashed-name squashed_0001_to_0020
# After all environments have applied the squash, delete the original files and remove the squash marker
```

### Fake-applying migrations (existing schema)
```bash
# Mark a migration as applied without running it
python manage.py migrate myapp 0001 --fake
python manage.py migrate --fake-initial   # initial migration on existing DB
```

## Configuration

### settings.py
```python
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.environ["DB_NAME"],
        "USER": os.environ["DB_USER"],
        "PASSWORD": os.environ["DB_PASSWORD"],
        "HOST": os.environ["DB_HOST"],
        "PORT": "5432",
    }
}
```

### CI migration check
```bash
# Fail CI if there are un-generated migrations
python manage.py makemigrations --check --dry-run
```

## Performance

### Large-table data migrations — avoid locking
```python
def backfill_in_batches(apps, schema_editor):
    User = apps.get_model("myapp", "User")
    # Process in chunks to reduce lock hold time
    qs = User.objects.filter(full_name__isnull=True).values_list("id", flat=True)
    ids = list(qs[:5000])
    while ids:
        User.objects.filter(id__in=ids).update(
            full_name=models.F("first_name")  # simplified
        )
        ids = list(qs[:5000])
```

For very large tables (>10M rows), use `atomic=False` and process outside a transaction to avoid long locks:
```python
class Migration(migrations.Migration):
    atomic = False
```

## Security
- Store DB credentials in environment variables; never hardcode in `settings.py`
- Migration user needs DDL rights; application runtime user needs DML only
- Never commit real data in `RunPython` migrations — use fixtures or management commands for seed data

## Testing
```bash
# Run migrations on a test database and verify no errors
python manage.py migrate --database=test_db

# In pytest (pytest-django)
@pytest.mark.django_db
def test_migration_completeness(transactional_db):
    call_command("migrate", "--check")
```
Use `django.test.utils.setup_test_environment` and run the full migration chain in CI. Test `RunPython` reverse functions explicitly.

## Dos
- Always provide a `reverse_code` in `RunPython` operations, even if it raises `migrations.RunPython.noop`
- Run `makemigrations --check` in CI to catch un-migrated model changes
- Use `iterator(chunk_size=...)` for large-table RunPython migrations to avoid loading all rows in memory
- Split DDL migrations from data migrations — separate files, separate deploys
- Use `sqlmigrate` to review SQL before applying in production
- Squash migrations in long-lived apps to keep the migration graph manageable

## Don'ts
- Never import live model classes directly inside migration functions — always use `apps.get_model()`
- Don't add business logic to migration files; keep them purely for schema and data transforms
- Avoid modifying a migration file that has been applied in any environment; create a new one
- Don't run `migrate` in production without first running it in staging with a production-scale data snapshot
- Avoid `--fake` in production without fully understanding the current schema state
- Never merge migration files from two long-lived branches without resolving the dependency graph
