# Flask + pytest Testing Patterns

> Flask-specific pytest patterns. Extends `modules/testing/pytest.md`.
> Generic pytest conventions (fixtures, parametrize, conftest layout) are not repeated here.

## Fixture Hierarchy

Three core fixtures, layered: `app` (session) -> `client` (function) -> per-feature fixtures.

```python
# tests/conftest.py
from __future__ import annotations
import pytest
from app import create_app
from app.extensions import db as _db

@pytest.fixture(scope="session")
def app():
    app = create_app("testing")
    with app.app_context():
        _db.create_all()
        yield app
        _db.session.remove()
        _db.drop_all()

@pytest.fixture
def client(app):
    return app.test_client()

@pytest.fixture
def runner(app):
    return app.test_cli_runner()
```

`app` is session-scoped — schema creation is expensive. Per-test isolation comes from the
transactional rollback fixture below, not from rebuilding the schema each test.

## Transactional Rollback

Rollback at the end of every test keeps tests independent without recreating the schema:

```python
# tests/conftest.py (continued)
@pytest.fixture
def db(app):
    """Per-test transaction that is rolled back at teardown."""
    with app.app_context():
        connection = _db.engine.connect()
        transaction = connection.begin()

        # Bind the session to this connection so commits inside the test
        # participate in the outer transaction (and get rolled back).
        _db.session.configure(bind=connection)

        yield _db

        _db.session.close()
        transaction.rollback()
        connection.close()
        _db.session.configure(bind=_db.engine)  # restore default binding
```

Tests that hit the DB depend on `db`:

```python
def test_create_user(db):
    user = User(email="a@b.com", password_hash="x")
    db.session.add(user)
    db.session.commit()                  # commits inside outer transaction
    assert db.session.scalar(db.select(db.func.count()).select_from(User)) == 1
# at teardown the outer transaction is rolled back; next test sees count=0
```

## TestConfig

```python
# app/config.py
class TestConfig(BaseConfig):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"  # or postgres testcontainer
    WTF_CSRF_ENABLED = False                         # tests submit forms directly
    SESSION_COOKIE_SECURE = False                    # tests run over HTTP
    SECRET_KEY = "test-secret"
    LOGIN_DISABLED = False                           # explicit; some tests opt in to disable
```

For tests that need real CSRF (security tests), use a parametrized config or override per-test:

```python
def test_form_requires_csrf(app):
    app.config["WTF_CSRF_ENABLED"] = True
    client = app.test_client()
    resp = client.post("/users", data={"email": "a@b.com"})
    assert resp.status_code == 400  # missing csrf_token
```

## API Testing with the Test Client

```python
def test_get_user(client, db, sample_user):
    resp = client.get(f"/api/v1/users/{sample_user.id}")
    assert resp.status_code == 200
    assert resp.get_json() == {"id": sample_user.id, "email": sample_user.email}

def test_create_user_validation(client, db):
    resp = client.post("/api/v1/users", json={"email": "not-an-email"})
    assert resp.status_code == 400
    assert "email" in resp.get_json()["errors"]
```

For HTML forms:

```python
def test_login_form(client, db, sample_user):
    resp = client.post(
        "/auth/login",
        data={"email": sample_user.email, "password": "secret"},
        follow_redirects=True,
    )
    assert resp.status_code == 200
    assert b"Welcome back" in resp.data
```

## Authenticated Requests with Flask-Login

```python
@pytest.fixture
def auth_client(client, sample_user):
    with client.session_transaction() as session:
        session["_user_id"] = str(sample_user.id)
        session["_fresh"] = True
    return client

def test_dashboard_requires_auth(client):
    resp = client.get("/dashboard")
    assert resp.status_code == 302  # redirect to login

def test_dashboard_when_authed(auth_client):
    resp = auth_client.get("/dashboard")
    assert resp.status_code == 200
```

## CLI Command Tests

```python
def test_create_admin_command(runner, db):
    result = runner.invoke(args=["create-admin", "admin@example.com"])
    assert result.exit_code == 0
    assert db.session.scalar(
        db.select(User).where(User.email == "admin@example.com")
    ).is_admin is True
```

`runner` invokes commands registered on the app via `app.cli.add_command(...)` or `@app.cli.command(...)`.

## Factory-Driven Test Data

Use `factory_boy` (or `polyfactory` for Pydantic) for object graphs. Avoid bare `User(...)` calls.

```python
# tests/factories/users.py
import factory
from factory.alchemy import SQLAlchemyModelFactory
from app.extensions import db
from app.features.users.models import User

class UserFactory(SQLAlchemyModelFactory):
    class Meta:
        model = User
        sqlalchemy_session = db.session
        sqlalchemy_session_persistence = "commit"

    email = factory.Sequence(lambda n: f"user{n}@example.com")
    password_hash = "hash"
    is_active = True
```

```python
# tests/conftest.py
@pytest.fixture
def sample_user(db):
    return UserFactory()
```

## Parametrized Config Classes

For tests that should run under multiple configs (e.g. with/without caching):

```python
@pytest.fixture(params=["testing", "testing_no_cache"])
def app(request):
    app = create_app(request.param)
    with app.app_context():
        _db.create_all()
        yield app
        _db.session.remove()
        _db.drop_all()
```

## Testing Blueprints in Isolation

Useful for shared blueprints (e.g. an admin blueprint reused across apps):

```python
def test_admin_blueprint():
    from flask import Flask
    from app.features.admin import admin_bp

    test_app = Flask(__name__)
    test_app.config["TESTING"] = True
    test_app.config["SECRET_KEY"] = "x"
    test_app.register_blueprint(admin_bp)

    client = test_app.test_client()
    resp = client.get("/admin/healthz")
    assert resp.status_code == 200
```

## What to Test at Each Layer

| Layer | Test type | Tools |
|-------|-----------|-------|
| Route / view | Integration | `client` + `db` fixtures + `client.get/post(...)` |
| Service | Unit + Integration | `db` fixture + factories |
| Form (FlaskForm) | Unit | Direct instantiation; no client needed |
| Schema (Marshmallow/Pydantic) | Unit | Direct `.load()/.dump()` calls |
| CLI command | Integration | `runner` + `db` |
| Model query / manager | Integration | `db` + factories |
| `before_request` / `after_request` | Integration | `client` to drive a request through the hooks |

## Common Pitfalls

- **Forgetting `app.app_context()`** in CLI tests -> `RuntimeError: Working outside of application context`
- **Module-level `app` import** -> tests can't swap config; refactor to `create_app("testing")`
- **`db.session.remove()` skipped** in teardown -> tests leak state across files
- **Using session-scoped `db` fixture** -> tests pollute each other; use the per-test rollback pattern
- **Asserting on `resp.json` instead of `resp.get_json()`** in older Flask -> `resp.json` was added in 1.0; both work in 3.x but `get_json()` is explicit

## Dos

- Session-scoped `app`, function-scoped `client`/`db`/`runner`
- Per-test transactional rollback for DB isolation — never recreate schema per test
- Disable CSRF in `TestConfig` by default; opt-in to CSRF tests explicitly
- Use factory_boy for model construction; avoid raw `Model(...)` for complex graphs
- Drive auth via `client.session_transaction()` setting `_user_id` — don't call login routes in every test
- Use `runner.invoke(args=[...])` for CLI tests; never shell out to `flask` binary

## Don'ts

- Don't import a module-level `app` into your tests — call `create_app("testing")` in the fixture
- Don't share the SQLAlchemy session across threads or processes — pytest-xdist needs per-worker DBs
- Don't assert on Werkzeug debugger HTML in error tests — assert on status code + JSON error body
- Don't use `client.cookie_jar` directly in Flask 3.x (removed) — use `session_transaction()` for session manipulation
- Don't leave `WTF_CSRF_ENABLED=True` in tests that submit forms via the test client (no token in `data=`) — the form will 400

For generic pytest patterns (parametrize, indirect fixtures, conftest layering) see `modules/testing/pytest.md`.
