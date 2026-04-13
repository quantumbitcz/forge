# FastAPI + Pytest Testing Conventions

## Test Structure

- Tests in `tests/` directory mirroring `app/` structure
- Name files: `test_<module>.py`
- Use `pytest` fixtures for shared setup
- Async tests: `@pytest.mark.anyio` or `@pytest.mark.asyncio`

## Client Testing

- Use `TestClient` from `starlette.testclient` for sync tests
- Use `httpx.AsyncClient` for async tests:
  ```python
  async with AsyncClient(app=app, base_url="http://test") as client:
      response = await client.get("/endpoint")
  ```
- Create client fixture: `@pytest.fixture` returning `TestClient(app)`

## Dependency Override

- Override dependencies per test:
  ```python
  app.dependency_overrides[get_db] = lambda: test_db
  ```
- Reset after test: `app.dependency_overrides.clear()`
- Use fixture with `yield` for automatic cleanup

## Database Testing

- Use Testcontainers for PostgreSQL: `PostgresContainer("postgres:16")`
- Create test database per session, rollback per test
- Async session fixture with `async_sessionmaker`
- Override `get_db` dependency to use test session

## Async Testing

- All test functions: `async def test_...` with `@pytest.mark.anyio`
- Use `anyio` over `asyncio` for broader compatibility
- Test background tasks with `await` on task completion

## Mocking

- `unittest.mock.patch` or `pytest-mock` for service mocking
- Override FastAPI dependencies instead of mocking internals
- Mock external HTTP with `respx` or `httpx_mock`

## Dos

- Test each endpoint: status code, response body, headers
- Test validation errors (422) with invalid input
- Test authentication/authorization per endpoint
- Test OpenAPI schema generation: `client.get("/openapi.json")`
- Use `conftest.py` for shared fixtures

## Don'ts

- Don't test Pydantic model validation separately (test through endpoints)
- Don't use `requests` library (use `TestClient` or `httpx`)
- Don't share database state between tests
- Don't test framework internals (dependency injection mechanics)
- Don't use `time.sleep` in async tests (use `anyio.sleep`)
