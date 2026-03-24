# PostgreSQL with FastAPI

## Integration Setup

```bash
# requirements.txt / pyproject.toml
asyncpg==0.29.0
sqlalchemy[asyncio]==2.0.30
alembic==1.13.1
databases[asyncpg]==0.9.0         # Optional: query-level async without full ORM
```

```python
# config.py
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str = "postgresql+asyncpg://user:pass@localhost:5432/mydb"
    db_pool_size: int = 5
    db_max_overflow: int = 10
    db_pool_timeout: int = 30

    class Config:
        env_file = ".env"
```

## Framework-Specific Patterns

### Dependency Injection for DB Sessions

```python
# database.py
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

engine = create_async_engine(
    settings.database_url,
    pool_size=settings.db_pool_size,
    max_overflow=settings.db_max_overflow,
    pool_timeout=settings.db_pool_timeout,
    echo=False,
)
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        yield session
```

```python
# router.py
@router.get("/orders/{order_id}")
async def get_order(
    order_id: UUID,
    db: AsyncSession = Depends(get_db),
) -> OrderResponse:
    ...
```

The `Depends(get_db)` pattern ensures the session is closed after the response — even on exceptions.

### asyncpg Direct Connection (high-throughput queries)

```python
import asyncpg

async def get_pool() -> asyncpg.Pool:
    return await asyncpg.create_pool(dsn=settings.database_url_raw, min_size=2, max_size=10)

# Lifespan
@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.db_pool = await get_pool()
    yield
    await app.state.db_pool.close()
```

Use `asyncpg` directly for bulk inserts and complex reporting queries where SQLAlchemy's overhead matters.

### Alembic Integration

Run migrations at container startup before the app starts:

```dockerfile
CMD alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## Scaffolder Patterns

```yaml
patterns:
  db_module: "app/database.py"
  settings: "app/config.py"
  alembic_dir: "alembic/"
  env_py: "alembic/env.py"
  migration_dir: "alembic/versions/"
```

## Additional Dos/Don'ts

- DO use `expire_on_commit=False` in `async_sessionmaker` — avoids lazy-load errors after commit in async context
- DO run `alembic upgrade head` in the Docker entrypoint, not at module import time
- DO use `asyncpg` URL format (`postgresql+asyncpg://`) for async engines
- DON'T use synchronous `psycopg2` drivers with async FastAPI — blocks the event loop
- DON'T share a session across requests or background tasks
