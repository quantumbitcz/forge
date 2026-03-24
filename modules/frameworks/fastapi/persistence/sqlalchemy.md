# SQLAlchemy with FastAPI

## Integration Setup

```bash
sqlalchemy[asyncio]==2.0.30
asyncpg==0.29.0
```

```python
# models.py — use SQLAlchemy 2.0 mapped_column style
class Base(DeclarativeBase):
    pass

class Order(Base):
    __tablename__ = "orders"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    customer_id: Mapped[uuid.UUID] = mapped_column(nullable=False, index=True)
    status: Mapped[str] = mapped_column(String(50), default="PENDING")
```

## Framework-Specific Patterns

### AsyncSession Dependency (per-request lifecycle)

```python
# deps.py
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import AsyncSessionLocal

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
```

The `commit` in the happy path and `rollback` on exception belong in the dependency, not in every endpoint.

### Async Engine Config

```python
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker

engine = create_async_engine(
    settings.database_url,          # postgresql+asyncpg://...
    pool_size=5,
    max_overflow=10,
    pool_recycle=3600,              # Recycle connections hourly
    pool_pre_ping=True,             # Test connection before use
    echo=settings.debug,
)
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)
```

### Repository Pattern with FastAPI

```python
class OrderRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def find_by_id(self, order_id: UUID) -> Order | None:
        result = await self.db.execute(
            select(Order).where(Order.id == order_id)
        )
        return result.scalar_one_or_none()

# Router
async def get_order_repo(db: AsyncSession = Depends(get_db)) -> OrderRepository:
    return OrderRepository(db)

@router.get("/orders/{order_id}")
async def get_order(
    order_id: UUID,
    repo: OrderRepository = Depends(get_order_repo),
) -> OrderResponse:
    order = await repo.find_by_id(order_id)
    if not order:
        raise HTTPException(404)
    return OrderResponse.model_validate(order)
```

### Lazy Loading is Disabled in Async

SQLAlchemy async mode does NOT support implicit lazy loading. Use `selectinload` or `joinedload` explicitly:

```python
result = await db.execute(
    select(Order).options(selectinload(Order.items)).where(Order.id == order_id)
)
```

## Scaffolder Patterns

```yaml
patterns:
  models: "app/models/{entity}.py"
  repository: "app/repositories/{entity}_repository.py"
  deps: "app/deps.py"
  database: "app/database.py"
```

## Additional Dos/Don'ts

- DO use `mapped_column` with `Mapped[T]` type hints (SQLAlchemy 2.0 style) — not `Column()`
- DO set `pool_pre_ping=True` to detect stale connections after DB restart
- DO use `expire_on_commit=False` to avoid post-commit lazy-load errors
- DON'T use `lazy="joined"` or any implicit lazy strategy in async context
- DON'T call `db.commit()` inside repositories — commit at the dependency/service boundary
