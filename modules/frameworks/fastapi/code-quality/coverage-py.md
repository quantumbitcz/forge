# FastAPI + coverage-py

> Extends `modules/code-quality/coverage-py.md` with FastAPI-specific integration.
> Generic coverage-py conventions (branch coverage, parallel runs, CI integration) are NOT repeated here.

## Integration Setup

FastAPI tests use `httpx.AsyncClient` with `pytest-asyncio` — configure coverage to handle async test execution:

```toml
[tool.coverage.run]
source = ["app"]
branch = true
omit = [
    "app/main.py",          # startup/shutdown event handlers — tested via integration
    "app/__init__.py",
    "*/__init__.py",
    "tests/*",
    "conftest.py",
]
parallel = true

[tool.coverage.report]
show_missing = true
skip_empty = true
precision = 2
exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "raise NotImplementedError",
    "if TYPE_CHECKING:",
    "@(abc\\.)?abstractmethod",
    "\\.\\.\\.",
]
fail_under = 80

[tool.pytest.ini_options]
asyncio_mode = "auto"
addopts = "--cov=app --cov-report=term-missing --cov-report=xml --cov-fail-under=80"
```

## Framework-Specific Patterns

### Async Coverage with pytest-asyncio

Install `pytest-asyncio` and `anyio` alongside coverage:

```bash
pip install pytest-asyncio anyio httpx coverage[toml]
```

Configure `asyncio_mode = "auto"` — avoids decorating every async test with `@pytest.mark.asyncio`:

```python
# conftest.py
import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app

@pytest.fixture
async def client() -> AsyncClient:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
```

### httpx.AsyncClient Test Pattern

Use `ASGITransport` to run the FastAPI app in-process — no network overhead, full coverage instrumentation:

```python
async def test_create_user(client: AsyncClient) -> None:
    response = await client.post(
        "/users/",
        json={"email": "user@example.com", "password": "secret123"},
    )
    assert response.status_code == 201
    assert response.json()["email"] == "user@example.com"
```

Coverage tracks lines executed inside FastAPI dependency resolution, middleware, and route handlers when the app runs in-process via `ASGITransport`.

### `--cov=app` Scope

Set `--cov=app` (the application package) rather than `--cov=.` — avoids instrumenting test files, virtual environments, and config modules that inflate the miss count:

```toml
[tool.pytest.ini_options]
addopts = "--cov=app --cov-report=term-missing --cov-report=xml"
```

For projects with multiple sub-packages:

```toml
addopts = "--cov=app --cov=shared --cov-report=term-missing --cov-report=xml"
```

### Lifespan Coverage

FastAPI `lifespan` startup/shutdown handlers are invoked by `ASGITransport` during test client setup — they are covered without special configuration when using the async client fixture pattern above.

## Additional Dos

- Use `ASGITransport(app=app)` with `httpx.AsyncClient` — it runs the FastAPI ASGI app in-process and provides complete coverage of middleware, dependency resolution, and error handlers.
- Set `asyncio_mode = "auto"` in `[tool.pytest.ini_options]` — avoids missing coverage from async tests not marked with the asyncio mark.
- Include `app/dependencies.py` and `app/middleware.py` in coverage source — FastAPI dependency and middleware code is often undertested.

## Additional Don'ts

- Don't use `requests.TestClient` (Starlette's sync client) for async endpoint tests — it covers the sync wrapper but not the actual async execution path inside handlers.
- Don't omit `app/routers/` directories from coverage — router files contain handler logic; missing coverage there hides untested business rules.
- Don't set `fail_under = 100` for FastAPI apps with background tasks or streaming endpoints — `BackgroundTasks` and `StreamingResponse` paths are hard to cover without integration tests.
