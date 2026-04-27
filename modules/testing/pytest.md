# pytest Testing Conventions
> Support tier: contract-verified
## Test Structure

All test files use the `test_` prefix. Organize by module: `tests/unit/`, `tests/integration/`, `tests/e2e/`. Mirror the source package layout inside each tier. Place shared fixtures and plugins in `conftest.py` at the appropriate directory level.

```
tests/
  conftest.py          # project-wide fixtures
  unit/
    conftest.py        # unit-only fixtures
    test_user_service.py
  integration/
    test_user_api.py
```

## Naming

- File: `test_{module_name}.py`
- Class (optional grouping): `TestUserService` — no `__init__` needed
- Function: `test_{action}_{context}` or `test_{expected_outcome}`
- Descriptive names beat short names — `test_create_user_returns_id_when_valid` is fine

## Assertions / Matchers

Use plain `assert` — pytest rewrites assertions to show helpful diffs:

```python
assert result == expected
assert item in collection
assert response.status_code == 200
assert user is None
assert "error" in message.lower()
```

Never use `assertEqual`, `assertTrue`, etc. — that is `unittest` style and produces inferior error output in pytest.

## Lifecycle / Fixtures

```python
@pytest.fixture
def user_repo(db_session):          # function scope by default
    return UserRepository(db_session)

@pytest.fixture(scope="module")
def api_client():                   # created once per test module
    return TestClient(app)

@pytest.fixture(scope="session")
def db_engine():                    # created once for entire test run
    ...

@pytest.fixture(autouse=True)
def reset_cache():                  # applied to every test automatically
    cache.clear()
    yield
    cache.clear()
```

Use `yield` fixtures for teardown — cleaner than `request.addfinalizer`.

## Parametrize

```python
@pytest.mark.parametrize("email,valid", [
    ("user@example.com", True),
    ("not-an-email",     False),
    ("",                 False),
])
def test_email_validation(email, valid):
    assert validate_email(email) == valid
```

Use `ids=` parameter for readable test names when inputs are complex objects.

## Async Testing

```python
@pytest.mark.asyncio
async def test_fetch_user():
    user = await user_service.fetch("uid-1")
    assert user.name == "Alice"
```

Configure `asyncio_mode = "auto"` in `pytest.ini` / `pyproject.toml` to avoid repeating the marker.

## Markers for Categorization

```python
@pytest.mark.slow           # excluded from default run: pytest -m "not slow"
@pytest.mark.integration    # requires live DB/network
@pytest.mark.smoke          # critical path subset
```

Register custom markers in `pyproject.toml` under `[tool.pytest.ini_options]` to suppress warnings.

## What NOT to Test

- SQLAlchemy model field definitions — test repository behaviour, not ORM metadata
- Pydantic model parsing of valid, trivial inputs — trust the library
- Framework routing mechanics (FastAPI path registration) — test handlers, not the router
- Environment variable loading logic in isolation — test the integrated config object

## Anti-Patterns

- Hardcoding paths or environment-specific values in test bodies — use fixtures or `tmp_path`
- Fixtures with side effects that are not cleaned up in `yield` teardown
- Testing a single function in isolation when it only makes sense end-to-end
- `time.sleep()` for timing-dependent tests — use `freezegun` or mock `datetime.now`
- Importing from `conftest.py` directly — fixtures are injected, never imported
- Giant fixture files — split by domain, keep each `conftest.py` focused
