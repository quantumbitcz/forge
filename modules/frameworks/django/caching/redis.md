# Django + Redis Caching (django-redis)

> Django-specific patterns for caching via django-redis. Extends generic Django conventions.

## Integration Setup

```bash
pip install django-redis
```

```python
# settings.py
CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": env("REDIS_URL", default="redis://localhost:6379/1"),
        "OPTIONS": {
            "CLIENT_CLASS": "django_redis.client.DefaultClient",
            "CONNECTION_POOL_KWARGS": {"max_connections": 10},
            "SOCKET_CONNECT_TIMEOUT": 5,
            "SOCKET_TIMEOUT": 5,
            "IGNORE_EXCEPTIONS": False,
        },
        "KEY_PREFIX": "myapp",
        "TIMEOUT": 300,         # default 5 min TTL
    }
}

# Use Redis as session backend
SESSION_ENGINE = "django.contrib.sessions.backends.cache"
SESSION_CACHE_ALIAS = "default"
```

## Framework-Specific Patterns

### `cache_page` decorator (view-level caching)

```python
# views.py
from django.views.decorators.cache import cache_page
from django.views.decorators.vary import vary_on_headers

@cache_page(60 * 5)                  # 5 minutes
@vary_on_headers("Accept-Language")
def product_list(request):
    products = Product.objects.select_related("category").all()
    return JsonResponse({"products": list(products.values())})
```

### Low-level cache API

```python
from django.core.cache import cache

def get_user(user_id: int) -> dict | None:
    key = f"user:{user_id}"
    cached = cache.get(key)
    if cached is not None:
        return cached
    try:
        user = User.objects.get(pk=user_id)
    except User.DoesNotExist:
        return None
    data = {"id": user.id, "email": user.email}
    cache.set(key, data, timeout=600)
    return data

def invalidate_user(user_id: int) -> None:
    cache.delete(f"user:{user_id}")
```

### Template fragment caching

```django
{% load cache %}
{% cache 300 sidebar request.user.id %}
  <!-- expensive sidebar HTML -->
{% endcache %}
```

### Cache versioning for bulk invalidation

```python
from django_redis import get_redis_connection

def invalidate_prefix(prefix: str) -> None:
    """Delete all keys matching prefix (use SCAN, not KEYS in production)."""
    conn = get_redis_connection("default")
    full_prefix = f"myapp:{prefix}:*"
    cursor = 0
    while True:
        cursor, keys = conn.scan(cursor, match=full_prefix, count=100)
        if keys:
            conn.delete(*keys)
        if cursor == 0:
            break
```

## Scaffolder Patterns

```
config/
  settings/
    base.py               # CACHES config
    test.py               # LocMemCache override for tests
app_name/
  services/
    cache_service.py      # get/set/invalidate helpers
  views.py                # @cache_page usage
```

## Dos

- Set `KEY_PREFIX` to isolate keys per application in shared Redis instances
- Override `CACHES` in `test.py` settings to use `LocMemCache` or `DummyCache` — avoid hitting Redis in unit tests
- Use `cache.get_or_set(key, callable, timeout)` for atomic fetch-or-populate to avoid thundering herd
- Use `SCAN` (not `KEYS`) for pattern-based invalidation in production keyspaces

## Don'ts

- Don't cache `QuerySet` objects — they are lazy and may trigger DB queries on unpickling; cache plain dicts or lists
- Don't set `IGNORE_EXCEPTIONS: True` in production silently — log cache failures to detect Redis outages
- Don't use `cache_page` on views returning user-specific data without `@vary_on_headers("Cookie")` or `@vary_on_cookie`
- Don't use the default `db: 0` for caching if you also use Redis for Celery — use separate DB indices
