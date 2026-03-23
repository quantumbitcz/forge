# FastAPI + pytest Testing Patterns

> FastAPI-specific testing patterns for pytest. Extends `modules/testing/pytest.md`.

## Test Client

- Use `httpx.AsyncClient` with `ASGITransport` for async integration tests
- Alternative: `TestClient` from `starlette.testclient` for sync tests

```python
import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app

@pytest.fixture
async def client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac

@pytest.mark.asyncio
async def test_create_user(client: AsyncClient):
    response = await client.post("/api/users", json={"name": "Alice"})
    assert response.status_code == 201
    assert response.json()["name"] == "Alice"
```

## Database Testing

- Use test database with transaction rollback per test or testcontainers
- Override the DB session dependency in tests
- Use factories (`factory_boy` or fixture functions) for test data

```python
@pytest.fixture
async def db_session():
    async with async_test_engine.connect() as conn:
        async with conn.begin() as txn:
            yield AsyncSession(bind=conn)
            await txn.rollback()
```

## Dependency Overrides

- Override `Depends()` callables for isolated testing
- `app.dependency_overrides[get_db] = override_get_db`
- Reset overrides in fixture teardown

## Fixtures

- Shared fixtures in `conftest.py`: `async_client`, `db_session`, factory fixtures
- Use `pytest.mark.parametrize` for testing multiple input variants
- Use `pytest.mark.asyncio` for all async test functions
