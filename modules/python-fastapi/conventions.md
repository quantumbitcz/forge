# Python/FastAPI Agent Conventions Reference

> Full details in project CLAUDE.md. This is a curated subset for agent consumption.

## Architecture (Router / Service / Repository)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `routers/` | HTTP endpoints, request validation, response serialization | services |
| `services/` | Business logic, orchestration, transaction boundaries | repositories, models |
| `repositories/` | Data access, SQLAlchemy queries | models, database session |
| `models/` | SQLAlchemy ORM models (database schema) | SQLAlchemy only |
| `schemas/` | Pydantic models for request/response validation | Pydantic only |
| `migrations/` | Alembic database migrations | models |

**Dependency rule:** Routers never import from repositories directly. Services mediate all data access.

## Async by Default

- All endpoint handlers must be `async def`, not `def`
- All database operations use `AsyncSession` from SQLAlchemy
- Background tasks use `BackgroundTasks` or Celery/ARQ for heavy work
- Use `asyncio.gather()` for concurrent I/O, never `threading`

## Dependency Injection

- Use `Depends()` for all cross-cutting concerns: DB sessions, auth, config
- Define reusable dependencies in `dependencies/` or `deps.py`
- Scoped sessions via `async_session_maker` yielded from a dependency
- Never instantiate services/repositories at module level

```python
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_maker() as session:
        yield session

async def get_user_service(db: AsyncSession = Depends(get_db)) -> UserService:
    return UserService(UserRepository(db))
```

## Pydantic Models (Schemas)

- All request bodies and responses must use Pydantic `BaseModel` subclasses
- Never return raw dicts from endpoints
- Use `model_config = ConfigDict(from_attributes=True)` for ORM compatibility
- Separate schemas: `XxxCreate`, `XxxUpdate`, `XxxResponse`, `XxxInDB`
- Use `Field()` for validation constraints and OpenAPI documentation

## SQLAlchemy Async

- Use `DeclarativeBase` with `mapped_column()` and `Mapped[]` type annotations
- All queries through `AsyncSession` — `session.execute(select(...))`, not legacy Query API
- Relationships use `lazy="selectin"` or explicit eager loading — never lazy loading in async context
- Use `selectinload()` / `joinedload()` for relationship prefetching

## Alembic Migrations

- Auto-generate with `alembic revision --autogenerate -m "description"`
- Always review generated migrations before applying
- Migration filenames: `{revision}_{description}.py`
- Downgrade path required for every migration

## Package Structure

```
app/
  main.py              # FastAPI app factory, middleware, lifespan
  routers/             # Route handlers grouped by domain
    {area}.py
  services/            # Business logic
    {area}_service.py
  repositories/        # Data access
    {area}_repository.py
  models/              # SQLAlchemy ORM models
    {area}.py
  schemas/             # Pydantic request/response models
    {area}.py
  dependencies/        # Shared Depends() callables
  migrations/          # Alembic migrations
  core/                # Config, security, exceptions
```

## Naming Patterns

| Artifact | Pattern | Example |
|----------|---------|---------|
| Router | `{area}_router` | `user_router` |
| Service | `{Area}Service` | `UserService` |
| Repository | `{Area}Repository` | `UserRepository` |
| ORM Model | `{Area}` (singular) | `User` |
| Create Schema | `{Area}Create` | `UserCreate` |
| Update Schema | `{Area}Update` | `UserUpdate` |
| Response Schema | `{Area}Response` | `UserResponse` |
| Migration | `{rev}_{description}` | `001_create_users_table` |

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels
- Docstrings on public service methods — explain WHY, not WHAT
- No `print()` in production code — use `logging` or `structlog`
- Type hints on all function signatures and return types
- No bare `except:` — always catch specific exceptions
- Max line length: 120 (ruff default)

## Error Handling

| Exception | HTTP Status |
|-----------|-------------|
| `ValueError` | 400 |
| `NotFoundException` (custom) | 404 |
| `PermissionError` | 403 |
| `ConflictException` (custom) | 409 |
| Unhandled | 500 (with structured error response) |

- Use custom exception classes inheriting from a base `AppException`
- Register exception handlers in `main.py` via `app.exception_handler()`
- Always return structured JSON error responses: `{"detail": "...", "code": "..."}`

## Testing

- **Framework:** pytest with pytest-asyncio
- **Client:** `httpx.AsyncClient` with `ASGITransport` for integration tests
- **Database:** Test database with transaction rollback per test or testcontainers
- **Fixtures:** Shared via `conftest.py` — `async_client`, `db_session`, factory fixtures
- **Factories:** Use `factory_boy` or plain fixture functions for test data
- **Rules:** Test behavior not implementation, one assertion focus per test, use parametrize for variants

## Security

- JWT Bearer auth via OAuth2PasswordBearer or custom scheme
- `Depends(get_current_user)` on all protected endpoints
- Password hashing via `passlib` / `bcrypt`
- CORS configured in `main.py` — restrictive origins in production
- Rate limiting via middleware (e.g., `slowapi`)

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated files, changing APIs, fixing pre-existing bugs.

## Dos and Don'ts

### Do
- Use `async def` for route handlers only when all I/O within is also async — FastAPI runs `def` handlers in a thread pool automatically, which is safer for sync I/O
- Use Pydantic `model_validator` for cross-field validation
- Use dependency injection (`Depends()`) for shared logic (auth, DB sessions, rate limiting)
- Return typed response models from all endpoints — never return raw dicts
- Use `BackgroundTasks` for fire-and-forget operations (email, logging)
- Use `httpx.AsyncClient` for outbound HTTP calls — never `requests` in async context

### Don't
- Don't use synchronous I/O in async handlers — it blocks the event loop for ALL requests
- Don't use `time.sleep()` — use `asyncio.sleep()` in async context
- Don't return database models directly from endpoints — use response DTOs
- Don't use global mutable state — use dependency injection or context variables
- Don't catch `Exception` in handlers — let FastAPI's exception handlers manage errors
- Don't use `print()` — use structured logging with `structlog` or `logging`

## Async Anti-Patterns

- **Blocking the event loop:** `open()`, `os.path.exists()`, `requests.get()` are all blocking. Use `aiofiles`, `asyncio.to_thread()`, `httpx.AsyncClient`
- **CPU-bound in async:** Don't do heavy computation in async handlers — offload to `asyncio.to_thread()` or a background worker
- **Missing await:** Forgetting `await` on a coroutine silently returns a coroutine object instead of the result

## Performance

- Use connection pooling for databases: `asyncpg` pool (min=5, max=20 per worker)
- Use `orjson` for fast JSON serialization (3-10x faster than stdlib `json`)
- Cache expensive queries with Redis or in-memory LRU cache (`@lru_cache` for pure functions)
- Profile with `py-spy` for production bottlenecks
