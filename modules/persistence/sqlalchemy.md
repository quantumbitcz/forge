# SQLAlchemy 2.0+ Best Practices

## Overview
SQLAlchemy 2.0+ is the standard Python ORM/SQL toolkit with both Core (expression language) and ORM layers, and full async support via `AsyncSession`. Use it for Python applications needing a mature ORM with rich querying capabilities. Avoid the legacy 1.x Query API in new code — use `select()` statements with 2.0-style throughout.

## Architecture Patterns

### Model Definition
```python
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from sqlalchemy import ForeignKey, String, Numeric
from datetime import datetime

class Base(DeclarativeBase):
    pass

class User(Base):
    __tablename__ = "users"

    id:         Mapped[int]      = mapped_column(primary_key=True)
    email:      Mapped[str]      = mapped_column(String(255), unique=True, nullable=False)
    name:       Mapped[str]      = mapped_column(String(100), nullable=False)
    created_at: Mapped[datetime] = mapped_column(server_default="now()")

    # Relationship — lazy="selectin" for async compatibility
    orders: Mapped[list["Order"]] = relationship(back_populates="user",
                                                  lazy="selectin")

class Order(Base):
    __tablename__ = "orders"

    id:      Mapped[int]           = mapped_column(primary_key=True)
    user_id: Mapped[int]           = mapped_column(ForeignKey("users.id"), index=True)
    total:   Mapped[Numeric]       = mapped_column(Numeric(10, 2), nullable=False)
    status:  Mapped[str]           = mapped_column(String(20), default="pending")
    user:    Mapped["User"]        = relationship(back_populates="orders")
```

### Repository Pattern with AsyncSession
```python
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional

class UserRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def find_by_id(self, user_id: int) -> Optional[User]:
        result = await self._session.execute(
            select(User).where(User.id == user_id)
        )
        return result.scalar_one_or_none()

    async def find_with_orders(self, user_id: int) -> Optional[User]:
        result = await self._session.execute(
            select(User)
            .options(selectinload(User.orders).selectinload(Order.items))
            .where(User.id == user_id)
        )
        return result.scalar_one_or_none()

    async def save(self, user: User) -> User:
        self._session.add(user)
        await self._session.flush()  # get generated id without committing
        return user
```

### Unit of Work Pattern
```python
# FastAPI dependency injection pattern
async def get_session() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        async with session.begin():
            yield session
            # auto-commit on exit, rollback on exception

@router.post("/orders")
async def create_order(
    dto: CreateOrderDto,
    session: AsyncSession = Depends(get_session)
) -> OrderResponse:
    repo = OrderRepository(session)
    order = Order(user_id=dto.user_id, total=dto.total)
    await repo.save(order)
    return OrderResponse.from_orm(order)
```

### Hybrid Properties
```python
from sqlalchemy.ext.hybrid import hybrid_property

class Order(Base):
    __tablename__ = "orders"
    subtotal:  Mapped[Numeric] = mapped_column(Numeric(10, 2))
    tax_rate:  Mapped[Numeric] = mapped_column(Numeric(5, 4), default=0.2)

    @hybrid_property
    def total_with_tax(self) -> Numeric:
        return self.subtotal * (1 + self.tax_rate)

    @total_with_tax.expression
    def total_with_tax(cls):
        return cls.subtotal * (1 + cls.tax_rate)
```

## Configuration

```python
# database.py
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker

engine = create_async_engine(
    url=settings.DATABASE_URL,          # postgresql+asyncpg://...
    pool_size=10,
    max_overflow=5,
    pool_timeout=30,
    pool_recycle=1800,                  # recycle connections every 30 min
    echo=settings.DEBUG,               # log SQL in dev only
)

AsyncSessionLocal = async_sessionmaker(
    engine,
    expire_on_commit=False,            # prevent lazy-load after commit
    autocommit=False,
    autoflush=False,
)
```

## Performance

### Relationship Loading Strategies
```python
from sqlalchemy.orm import selectinload, joinedload, lazyload

# selectinload: separate IN query — best for collections in async
stmt = select(User).options(selectinload(User.orders))

# joinedload: single JOIN — best for single scalar relationships
stmt = select(Order).options(joinedload(Order.user))

# Avoid lazy loading in async — raises MissingGreenlet error
# lazy="raise" on relationships catches accidental lazy loads at dev time
orders: Mapped[list["Order"]] = relationship(lazy="raise")
```

### Bulk Operations
```python
# Bulk insert (Core — bypasses ORM events/validation)
await session.execute(
    insert(User),
    [{"email": u.email, "name": u.name} for u in new_users]
)

# Bulk update with RETURNING
result = await session.execute(
    update(Order)
    .where(Order.status == "pending", Order.created_at < cutoff)
    .values(status="expired")
    .returning(Order.id)
)
expired_ids = result.scalars().all()
```

### Query Optimization
```python
# Projection: select only needed columns
stmt = select(User.id, User.email).where(User.active == True)

# Pagination with keyset (avoid OFFSET on large tables)
stmt = select(Order).where(Order.id > last_seen_id).limit(20)
```

## Security

```python
# SAFE: all SQLAlchemy constructs are parameterized
stmt = select(User).where(User.email == user_input)

# SAFE: text() with explicit bound params
from sqlalchemy import text
stmt = text("SELECT * FROM users WHERE email = :email")
result = await session.execute(stmt, {"email": user_input})

# UNSAFE: never use Python f-strings or % in SQL text
# text(f"SELECT * FROM users WHERE email = '{user_input}'")  # SQL injection!
```

## Testing

```python
import pytest
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker

@pytest.fixture
async def session():
    engine = create_async_engine("postgresql+asyncpg://user:pass@localhost/test_db")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with async_sessionmaker(engine, expire_on_commit=False)() as s:
        yield s
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)

# With Testcontainers
@pytest.fixture(scope="session")
def postgres_url():
    with PostgresContainer("postgres:16-alpine") as pg:
        yield pg.get_connection_url().replace("postgresql", "postgresql+asyncpg")

@pytest.mark.asyncio
async def test_find_with_orders(session: AsyncSession):
    repo = UserRepository(session)
    user = await repo.find_with_orders(1)
    assert user is not None
    assert len(user.orders) > 0  # selectinload should have loaded this
```

## Dos
- Use `select()` statement API exclusively — never use the legacy `session.query(Model)` API.
- Set `expire_on_commit=False` on `async_sessionmaker` — prevents accidental lazy-loads after commit.
- Use `selectinload` for async collection loading — `lazy="select"` raises `MissingGreenlet` in async.
- Use `session.flush()` to get generated IDs within a transaction without committing.
- Set `lazy="raise"` on relationships in models to catch unintended lazy loads during development.
- Use Alembic for all schema migrations — never use `Base.metadata.create_all` in production.
- Use `mapped_column()` and `Mapped[T]` type annotations — the 2.0 declarative style provides IDE support and type safety.

## Don'ts
- Don't use `session.query(Model)` — it is the legacy 1.x API and deprecated in 2.0+.
- Don't use `lazy="select"` (default) with `AsyncSession` — it requires greenlet context that async lacks.
- Don't forget `await session.commit()` or rely on auto-commit in production — be explicit about transaction boundaries.
- Don't use `joinedload` on collections — it creates Cartesian products; use `selectinload` instead.
- Don't open `AsyncSession` without `expire_on_commit=False` and then access attributes after commit.
- Don't use `text()` with Python string formatting for user input — always use bound parameters.
- Don't use `session.execute(select(Model))` across long request pipelines without timeout handling.
