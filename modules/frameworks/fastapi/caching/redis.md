# FastAPI + Redis Caching

> FastAPI-specific patterns for caching via redis-py (async). Extends generic FastAPI conventions.

## Integration Setup

```bash
redis[asyncio]==5.0.3    # async support via redis.asyncio
```

```python
# app/redis_client.py
import redis.asyncio as redis
from app.config import settings

pool = redis.ConnectionPool.from_url(
    settings.redis_url,             # redis://localhost:6379/0
    max_connections=10,
    decode_responses=True,
)

async def get_redis() -> redis.Redis:
    return redis.Redis(connection_pool=pool)
```

## Framework-Specific Patterns

### Dependency injection for Redis

```python
from typing import Annotated
from fastapi import Depends
import redis.asyncio as aioredis

RedisDep = Annotated[aioredis.Redis, Depends(get_redis)]
```

### Cache decorator pattern

```python
import json, functools
from typing import Callable, Any

def cached(key_prefix: str, ttl: int = 300):
    """Async cache-aside decorator for FastAPI route handlers."""
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        async def wrapper(*args, redis: aioredis.Redis, **kwargs) -> Any:
            cache_key = f"{key_prefix}:{':'.join(str(v) for v in kwargs.values())}"
            hit = await redis.get(cache_key)
            if hit:
                return json.loads(hit)
            result = await func(*args, redis=redis, **kwargs)
            await redis.setex(cache_key, ttl, json.dumps(result, default=str))
            return result
        return wrapper
    return decorator
```

### Session-scoped cache via lifespan

```python
# app/main.py
from contextlib import asynccontextmanager
from fastapi import FastAPI

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Pool is created at module level — no setup needed
    yield
    await pool.aclose()

app = FastAPI(lifespan=lifespan)
```

### Endpoint with explicit cache-aside

```python
@router.get("/users/{user_id}")
async def get_user(user_id: UUID, redis: RedisDep, db: DbDep) -> UserResponse:
    key = f"users:{user_id}"
    cached = await redis.get(key)
    if cached:
        return UserResponse.model_validate_json(cached)
    user = await db.get_or_404(User, user_id)
    await redis.setex(key, 300, user.model_dump_json())
    return user
```

## Scaffolder Patterns

```yaml
patterns:
  redis_client: "app/redis_client.py"
  cache_utils:  "app/utils/cache.py"
  deps:         "app/deps.py"          # RedisDep alongside DbDep
```

## Additional Dos/Don'ts

- DO use a connection pool at module level — never create a new `Redis()` per request
- DO use `setex` (set + expire) atomically — never set then expire in two calls
- DO serialize with `model_dump_json()` / `model_validate_json()` for Pydantic models
- DON'T store raw Python objects — always serialize to JSON or msgpack
- DON'T skip error handling: wrap Redis calls in `try/except RedisError` and fall through to DB on cache miss
- DON'T use `decode_responses=False` when storing JSON strings — it causes double-encoding confusion
