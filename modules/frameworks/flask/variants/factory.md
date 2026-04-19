# Flask + Application Factory Variant

> Application factory pattern for Flask 3.x projects. Extends `modules/frameworks/flask/conventions.md`.
> This is the **default** variant for new Flask projects in this plugin — every other variant assumes
> the factory pattern as the foundation.

## Why Factories

Module-level `app = Flask(__name__)` ties the app to a single config and a single import lifecycle.
The factory pattern unlocks:

- **Per-test app instances** with isolated configs and databases
- **Conditional extension wiring** (skip Flask-Mail in tests, swap session backends)
- **Multiple deployment targets** (production app + management CLI app + worker app from one codebase)
- **Late-binding of `current_app`** so extensions and blueprints don't need a global app reference

## Anatomy

```python
# app/__init__.py
from __future__ import annotations
from flask import Flask
from app.config import BaseConfig
from app.extensions import db, migrate, login_manager, csrf, cache
from app.errors import register_error_handlers
from app.commands import register_commands

def create_app(config_name: str = "production") -> Flask:
    app = Flask(__name__, instance_relative_config=True)
    _load_config(app, config_name)

    _init_extensions(app)
    _register_blueprints(app)
    _register_jinja_globals(app)
    register_error_handlers(app)
    register_commands(app)

    return app

def _load_config(app: Flask, config_name: str) -> None:
    config_class = {
        "development": "app.config.DevConfig",
        "testing":     "app.config.TestConfig",
        "production":  "app.config.ProdConfig",
    }[config_name]
    app.config.from_object(config_class)
    app.config.from_pyfile("instance.cfg", silent=True)  # local overrides, never committed

def _init_extensions(app: Flask) -> None:
    db.init_app(app)
    migrate.init_app(app, db)
    login_manager.init_app(app)
    csrf.init_app(app)
    cache.init_app(app)

def _register_blueprints(app: Flask) -> None:
    from app.features.users import users_bp
    from app.features.posts import posts_bp
    app.register_blueprint(users_bp)
    app.register_blueprint(posts_bp)
```

## Config Class Hierarchy

```python
# app/config.py
import os
from datetime import timedelta

class BaseConfig:
    SECRET_KEY = os.environ["SECRET_KEY"]                    # raise early if missing
    SQLALCHEMY_DATABASE_URI = os.environ["DATABASE_URL"]
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {"pool_pre_ping": True, "pool_recycle": 280}

    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
    PERMANENT_SESSION_LIFETIME = timedelta(hours=8)

class DevConfig(BaseConfig):
    DEBUG = True
    SESSION_COOKIE_SECURE = False                            # dev over HTTP
    SQLALCHEMY_ECHO = True

class ProdConfig(BaseConfig):
    DEBUG = False
    SESSION_COOKIE_SECURE = True
    PREFERRED_URL_SCHEME = "https"

class TestConfig(BaseConfig):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"
    WTF_CSRF_ENABLED = False                                 # forms tested directly
    SESSION_COOKIE_SECURE = False
```

## Extensions Module

```python
# app/extensions.py
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_login import LoginManager
from flask_wtf.csrf import CSRFProtect
from flask_caching import Cache

db = SQLAlchemy()
migrate = Migrate()
login_manager = LoginManager()
csrf = CSRFProtect()
cache = Cache()
```

Singletons live at module scope so blueprints can `from app.extensions import db` without circular
imports. The factory wires them to a concrete app via `init_app(app)`.

## Application Context for CLI and Background Tasks

Code outside the request cycle (CLI commands, Celery tasks, REPL) must wrap database/session calls
in an explicit application context:

```python
from app import create_app

app = create_app("production")
with app.app_context():
    user = db.session.get(User, user_id)
    user.activate()
    db.session.commit()
```

Without the context manager, `current_app` and the SQLAlchemy session raise `RuntimeError: Working
outside of application context`.

## WSGI Entry Point

```python
# wsgi.py
import os
from app import create_app

app = create_app(os.environ.get("FLASK_ENV", "production"))
```

```bash
gunicorn --workers 4 --bind 0.0.0.0:8000 wsgi:app
```

## Per-Test App Instances

The factory enables fresh app state per test session — see `modules/frameworks/flask/testing/pytest.md`
for the canonical fixture. Brief preview:

```python
@pytest.fixture(scope="session")
def app():
    app = create_app("testing")
    with app.app_context():
        db.create_all()
        yield app
        db.session.remove()
        db.drop_all()
```

## Multiple App Variants from One Codebase

```python
# Web app (full HTTP surface)
app = create_app("production")

# Management CLI (no blueprints, just commands + db)
def create_cli_app():
    app = Flask(__name__)
    app.config.from_object("app.config.ProdConfig")
    db.init_app(app)
    register_commands(app)
    return app

# Worker (just db + queues, no HTTP)
def create_worker_app():
    app = Flask(__name__)
    app.config.from_object("app.config.ProdConfig")
    db.init_app(app)
    return app
```

## Dos

- Always use `create_app(config_name)` — even for the smallest project; the cost is one file
- Define config as classes in `app/config.py`; select via env var (`FLASK_ENV` or equivalent)
- Module-level extension singletons in `app/extensions.py`; wire with `init_app(app)` in the factory
- Wrap CLI / Celery / REPL code in `with app.app_context(): ...`
- Load secrets via `os.environ[...]` (raises KeyError if missing) — not `os.environ.get(...)`
- Use `instance_relative_config=True` so per-machine overrides don't pollute the repo

## Don'ts

- Don't put `app = Flask(__name__)` at module scope — defeats per-test isolation
- Don't init extensions at module scope (`db = SQLAlchemy(app)`) — defer the wiring to `init_app`
- Don't import `current_app` outside a request or `app_context()` — it returns a sentinel that raises on access
- Don't mix `app.config.from_object` and ad-hoc `app.config["KEY"] = ...` assignments — keep config in one place
- Don't depend on import-time side effects to register blueprints — register them explicitly inside the factory
