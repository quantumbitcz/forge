# PostgreSQL with Django

## Integration Setup

```bash
psycopg[binary]==3.1.19           # psycopg3 (preferred for new projects)
# OR: psycopg2-binary==2.9.9      # psycopg2 (legacy compatibility)
django-environ==0.11.2            # DATABASE_URL parsing
django-db-connection-pool==1.2.3  # Optional: SQLAlchemy-backed pooling
```

```python
# settings.py
import environ

env = environ.Env(DEBUG=(bool, False))
environ.Env.read_env(BASE_DIR / ".env")

DATABASES = {
    "default": env.db("DATABASE_URL", default="postgres://user:pass@localhost:5432/mydb")
}
# Equivalent to:
# DATABASES = {"default": {"ENGINE": "django.db.backends.postgresql", "NAME": ..., ...}}
```

## Framework-Specific Patterns

### django.contrib.postgres Fields

```python
from django.contrib.postgres.fields import ArrayField
from django.db.models import JSONField   # Built-in since Django 3.1

class Product(models.Model):
    tags = ArrayField(models.CharField(max_length=50), default=list)
    metadata = JSONField(default=dict)
    search_vector = SearchVectorField(null=True)  # For full-text search
```

`ArrayField` and `SearchVectorField` are PostgreSQL-only and live in `django.contrib.postgres`.

### Connection Pooling with django-db-connection-pool

```python
# settings.py (optional pool config)
DATABASES = {
    "default": {
        **env.db("DATABASE_URL"),
        "ENGINE": "dj_db_conn_pool.backends.postgresql",
        "POOL_OPTIONS": {
            "POOL_SIZE": 5,
            "MAX_OVERFLOW": 10,
            "RECYCLE": 3600,
            "PRE_PING": True,
        },
    }
}
```

Django's built-in connection handling uses persistent-per-thread connections (not a pool). Use `django-db-connection-pool` when running under async ASGI servers (Uvicorn + Django) or high-concurrency WSGI (Gunicorn + gevent).

### DATABASE_URL Format

```bash
# .env
DATABASE_URL=postgres://user:password@host:5432/dbname?sslmode=require
```

`django-environ` parses all standard DATABASE_URL parameters including `sslmode`, `connect_timeout`, and `options`.

## Scaffolder Patterns

```yaml
patterns:
  settings: "{project}/settings.py"
  env_file: ".env"
  env_example: ".env.example"
```

## Additional Dos/Don'ts

- DO add `django.contrib.postgres` to `INSTALLED_APPS` to use PostgreSQL-specific fields and indexes
- DO use `django-environ` or `python-decouple` — never hardcode DB credentials in settings
- DO set `CONN_MAX_AGE = 60` (or higher) in settings for persistent connections under WSGI
- DON'T use `ArrayField` if cross-DB portability is required — use a related model instead
- DON'T run Django under ASGI with default synchronous ORM without `sync_to_async` wrappers
