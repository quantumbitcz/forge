# FastAPI Framework Conventions
> Support tier: contract-verified
> Framework-specific conventions for FastAPI projects. Language idioms are in `modules/languages/python.md`. Generic testing patterns are in `modules/testing/pytest.md`.

## Architecture (Router / Service / Repository)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `routers/` | HTTP endpoints, request validation, response serialization | services |
| `services/` | Business logic, orchestration, transaction boundaries | repositories, models |
| `repositories/` | Data access, database queries | models, database session |
| `models/` | ORM/database models (schema definition depends on `persistence:` choice) | persistence layer only |
| `schemas/` | Pydantic models for request/response validation | Pydantic only |
| `migrations/` | Database migrations (tool depends on `persistence:` choice) | models |

**Dependency rule:** Routers never import from repositories directly. Services mediate all data access.

## Async by Default

- All endpoint handlers use `async def` when performing async I/O
- All database operations use async patterns (specifics depend on `persistence:` choice)
- Background tasks use `BackgroundTasks` or Celery/ARQ for heavy work
- Use `asyncio.gather()` for concurrent I/O, never `threading`

## Dependency Injection

- Use `Depends()` for all cross-cutting concerns: DB sessions, auth, config
- Define reusable dependencies in `dependencies/` or `deps.py`
- Scoped DB sessions yielded from a dependency
- Never instantiate services/repositories at module level

## Pydantic Models (Schemas)

- All request bodies and responses must use Pydantic `BaseModel` subclasses
- Never return raw dicts from endpoints
- Use `model_config = ConfigDict(from_attributes=True)` for ORM compatibility
- Separate schemas: `XxxCreate`, `XxxUpdate`, `XxxResponse`, `XxxInDB`
- Use `Field()` for validation constraints and OpenAPI documentation

## Data Access

Data access patterns depend on `components.persistence` — see the persistence binding file for details.

**Shared rules (all persistence layers):**
- All queries through async session/connection when using async I/O
- Parameterized queries only — no string interpolation in SQL
- Repository methods return domain types, not raw rows or ORM internals
- Migrations must have a downgrade/rollback path

## Naming Patterns

| Artifact | Pattern | Example |
|----------|---------|---------|
| Router | `{area}_router` | `user_router` |
| Service | `{Area}Service` | `UserService` |
| Repository | `{Area}Repository` | `UserRepository` |
| ORM Model | `{Area}` (singular) | `User` |
| Create Schema | `{Area}Create` | `UserCreate` |
| Response Schema | `{Area}Response` | `UserResponse` |
| Migration | `{rev}_{description}` | `001_create_users_table` |

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels
- Docstrings on public service methods -- explain WHY, not WHAT
- No `print()` in production code -- use `logging` or `structlog`
- No bare `except:` -- always catch specific exceptions

## Error Handling

| Exception | HTTP Status |
|-----------|-------------|
| `ValueError` | 400 |
| `NotFoundException` (custom) | 404 |
| `PermissionError` | 403 |
| `ConflictException` (custom) | 409 |
| Unhandled | 500 |

- Use custom exception classes inheriting from a base `AppException`
- Register exception handlers via `app.exception_handler()`
- Always return structured JSON error responses: `{"detail": "...", "code": "..."}`

## Security

- JWT Bearer auth via OAuth2PasswordBearer or custom scheme
- `Depends(get_current_user)` on all protected endpoints
- Password hashing via `passlib` / `bcrypt`
- CORS configured restrictively in production
- Rate limiting via middleware (e.g., `slowapi`)

## Performance

- Connection pooling: configure pool sizing per persistence driver (e.g., `asyncpg` min=5, max=20 per worker)
- Use `orjson` for fast JSON serialization (3-10x faster than stdlib)
- Cache expensive queries with Redis or in-memory LRU cache
- Profile with `py-spy` for production bottlenecks

## Testing

### Test Framework
- **pytest** with **pytest-asyncio** for async test support
- **httpx** `AsyncClient` with `ASGITransport` for testing FastAPI endpoints without a running server
- **factory_boy** or custom fixtures for test data generation

### Integration Test Patterns
- Use `AsyncClient` with the FastAPI app instance for full-stack endpoint tests
- Override dependencies via `app.dependency_overrides[get_db] = get_test_db` for test isolation
- Use **Testcontainers** (`testcontainers-python`) with a real PostgreSQL instance for database tests
- Test async service methods directly with `pytest.mark.asyncio`

### What to Test
- Endpoint request/response contracts: status codes, response shapes, validation errors
- Service-layer business rules with mocked repositories
- Repository queries against a real database (via Testcontainers)
- Custom exception handlers: verify structured error responses

### What NOT to Test
- Pydantic type validation (e.g., that `str` field rejects `int`) — Pydantic guarantees this
- `Depends()` resolution mechanics — FastAPI handles this
- ORM column type mapping (persistence layer guarantees this)
- OpenAPI schema generation

### Example Test Structure
```
tests/
  conftest.py                  # fixtures: app, async_client, test_db
  test_routers/
    test_user_router.py        # endpoint integration tests
  test_services/
    test_user_service.py       # unit tests with mocked repos
  test_repositories/
    test_user_repository.py    # Testcontainers DB tests
```

For general pytest patterns, see `modules/testing/pytest.md`.

## Smart Test Rules

- No duplicate tests — grep existing tests before writing new ones
- Test business behavior, not implementation details
- Do NOT test framework guarantees (e.g., Pydantic validates types, `Depends()` resolution, automatic OpenAPI generation)
- Do NOT test ORM column mapping or migration tool mechanics
- Each test scenario covers a unique code path
- Fewer meaningful tests > high coverage of trivial code

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated routers, changing dependency injection contracts, restructuring Pydantic models.

## Dos and Don'ts

### Do
- Use `async def` for route handlers only when all I/O is also async -- FastAPI runs `def` handlers in a thread pool automatically
- Use Pydantic `model_validator` for cross-field validation
- Use dependency injection (`Depends()`) for shared logic
- Return typed response models from all endpoints
- Use `BackgroundTasks` for fire-and-forget operations
- Use `httpx.AsyncClient` for outbound HTTP calls

### Don't
- Don't use synchronous I/O in async handlers -- blocks the event loop for ALL requests
- Don't use `time.sleep()` -- use `asyncio.sleep()` in async context
- Don't return database models directly -- use response DTOs
- Don't use global mutable state -- use dependency injection
- Don't catch `Exception` broadly in handlers -- let FastAPI manage errors
