# Flask Framework Conventions
> Support tier: contract-verified
> Framework-specific conventions for Flask 3.x projects. Language idioms are in `modules/languages/python.md`.
> Generic testing patterns are in `modules/testing/pytest.md`.
> Composition stack: `variant > flask/testing/pytest.md > flask/conventions.md > python.md > persistence/sqlalchemy.md > testing/pytest.md`.

## Overview

Flask is a microframework — it ships routing, request/response, templating (Jinja2), and a CLI; everything else (ORM, auth, forms, migrations) is an extension. Use Flask when:

- The HTTP surface is small-to-medium and you want explicit control over the extension stack
- You need a synchronous WSGI app deployable behind gunicorn / uWSGI / Waitress
- You prefer composing extensions over a batteries-included monolith

Prefer Django when you need the full admin/auth/ORM stack out of the box. Prefer FastAPI when async-first ASGI, automatic OpenAPI, and Pydantic validation are the primary requirements.

## Architecture (Application Factory + Blueprints + Services)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `app/__init__.py` (`create_app`) | App factory: load config, init extensions, register blueprints, set up error handlers | Config, extensions |
| `app/extensions.py` | Module-level extension singletons (`db`, `login_manager`, `migrate`, `csrf`) initialized via `init_app(app)` inside the factory | None |
| `app/{feature}/routes.py` (or `views.py`) | HTTP handling, form parsing, delegating to services, returning responses | Services, forms, schemas |
| `app/{feature}/services.py` | Business logic, use cases, orchestration | Models, repositories |
| `app/{feature}/models.py` | SQLAlchemy ORM models | Flask-SQLAlchemy `db` |
| `app/{feature}/forms.py` | Flask-WTF forms + validators | wtforms |
| `app/{feature}/schemas.py` | Marshmallow / Pydantic serializers for JSON APIs | (optional) |
| `app/{feature}/__init__.py` | `Blueprint(__name__, url_prefix=...)` definition + route imports | Flask |
| `migrations/` | Alembic migrations managed by Flask-Migrate | SQLAlchemy metadata |

**Dependency rule:** routes never contain business logic — they validate, delegate to services, return a response. Services mediate data access via models or repositories. Models are persistence representations. Forms validate browser input; schemas validate JSON. Cross-blueprint dependencies flow through service interfaces.

## Application Factory

Always use `create_app(config_name=None)` instead of module-level `app = Flask(__name__)`. The factory pattern enables:

- Multiple app instances per test (config swapping, isolated DBs)
- Conditional extension wiring (e.g. skip Flask-Mail in tests)
- Late-binding of `current_app` via the application context

```python
# app/__init__.py
from flask import Flask
from app.extensions import db, login_manager, migrate, csrf

def create_app(config_name: str = "production") -> Flask:
    app = Flask(__name__, instance_relative_config=True)
    app.config.from_object(f"app.config.{config_name.capitalize()}Config")

    db.init_app(app)
    migrate.init_app(app, db)
    login_manager.init_app(app)
    csrf.init_app(app)

    from app.users import users_bp
    from app.posts import posts_bp
    app.register_blueprint(users_bp)
    app.register_blueprint(posts_bp)

    register_error_handlers(app)
    return app
```

CLI commands and shell access must wrap calls in `with app.app_context(): ...`.

## Blueprints

- One blueprint per feature/bounded context: `users`, `posts`, `billing`
- Blueprints own their templates (`template_folder=`) and static files (`static_folder=`) when feature-scoped
- `url_prefix=` declared at blueprint construction, never per-route
- Avoid nested blueprints unless absolutely needed — prefer flat composition
- Register all blueprints inside `create_app`; never at import time

```python
# app/users/__init__.py
from flask import Blueprint

users_bp = Blueprint(
    "users",
    __name__,
    url_prefix="/users",
    template_folder="templates",
    static_folder="static",
)

from app.users import routes  # noqa: E402,F401  registers routes on users_bp
```

## Routing

- Use decorator routing: `@bp.route("/<int:user_id>", methods=["GET"])`
- Type converters for path params: `<int:>`, `<uuid:>`, `<path:>` — never trust raw strings
- Always specify `methods=` explicitly, even for GET — makes intent clear and enables 405 handling
- Use `url_for("users.show", user_id=u.id)` in templates and redirects — never hardcode URLs
- Register error handlers per-app (`@app.errorhandler(404)`) and per-blueprint (`@bp.errorhandler(...)`) for scoped behavior

## Templating (Jinja2)

- Autoescape is on by default — never disable globally
- Use `url_for()` in templates; never construct URLs by string concatenation
- Use macros for repeated form widgets / field rendering
- Context processors (`@app.context_processor`) inject globals (e.g. `current_year`, brand strings) — keep small
- Never call `Markup()` on user-supplied content; if HTML must be rendered, sanitize first with `bleach`
- Template inheritance: a single `base.html` with `{% block content %}` per major surface

## Persistence (Flask-SQLAlchemy 3.x)

- Use the SQLAlchemy 2.0 style: `db.session.execute(db.select(Model)).scalars().all()` rather than the legacy `Model.query`
- Define models with `db.Model` as base (`class User(db.Model): ...`)
- Use `db.session.commit()` exactly once per request via an `after_request` handler or explicit service-layer commit; rollback on exception
- Eager-load relationships with `selectinload()` / `joinedload()` to prevent N+1 — never rely on lazy loading inside templates
- Configure connection pooling via `SQLALCHEMY_ENGINE_OPTIONS = {"pool_pre_ping": True, "pool_recycle": 280}` for long-running gunicorn workers
- Use `db.session.scalar(db.select(Model).where(...))` for single-row reads instead of `.first()` on a query

### Migrations (Flask-Migrate / Alembic)

```bash
flask db init           # one-time, creates migrations/
flask db migrate -m "add posts table"
flask db upgrade
flask db downgrade -1   # always reversible
```

- Every autogenerated migration must be reviewed manually before commit — Alembic misses indexes, server defaults, and enum changes
- Data migrations live in the `upgrade()`/`downgrade()` body using raw `op.execute(...)` or session ops; both directions required

## Forms and Validation (Flask-WTF)

- Use `FlaskForm` subclasses for all browser-submitted forms; validators in the field definition, not in the route
- CSRF is automatic via `CSRFProtect` — every `<form method="post">` template must include `{{ form.csrf_token }}` (or `{{ csrf_token() }}` for raw forms)
- For JSON APIs, use Marshmallow or Pydantic schemas; CSRF is bypassed via `@csrf.exempt` on those routes — protect them with token auth instead
- Cross-field validation: override `validate(self)` on the form class

## Authentication and Authorization (Flask-Login)

- `LoginManager.user_loader` reloads the user from the session ID on each request — keep it cheap (single indexed lookup)
- Decorate protected routes with `@login_required`; check roles/permissions inside the view via `current_user.can(...)` or a custom decorator
- Session cookie config (production):
  - `SESSION_COOKIE_SECURE = True`
  - `SESSION_COOKIE_HTTPONLY = True`
  - `SESSION_COOKIE_SAMESITE = "Lax"` (or `"Strict"` for high-security)
  - `PERMANENT_SESSION_LIFETIME = timedelta(hours=8)`
- Token auth for APIs: itsdangerous `URLSafeTimedSerializer` for short-lived tokens; Authlib for OAuth2 / OIDC

## Security

- `SECRET_KEY`: load from env var (`os.environ["SECRET_KEY"]`) — never commit; rotation invalidates sessions
- Never run `app.run(debug=True)` in production — the Werkzeug debugger executes arbitrary code
- CORS: configure narrowly via Flask-CORS — never `origins="*"` for credentialed endpoints
- SQL injection: handled by SQLAlchemy parameter binding — never string-concat into `text()` or `execute(...)`
- XSS: Jinja2 autoescape on; sanitize before `Markup(...)` if you must render HTML
- Sensitive headers via Flask-Talisman: HSTS, CSP, X-Frame-Options, Referrer-Policy
- File uploads: `secure_filename()` on every uploaded filename; validate MIME via the file body, not the extension
- Rate limiting: Flask-Limiter with Redis backend for distributed limits

## Performance

- gunicorn worker sizing: `(2 × CPU) + 1` sync workers, or fewer with `gevent`/`eventlet` async workers for I/O-bound apps
- Connection pool: `SQLALCHEMY_ENGINE_OPTIONS = {"pool_size": 10, "max_overflow": 20, "pool_pre_ping": True}`
- Caching: Flask-Caching with Redis backend; `@cache.memoize(timeout=...)` for expensive view fragments
- `before_request` / `after_request` hooks run on every request — keep them fast (target < 5 ms total) and avoid DB queries
- Use `lazy=False` only when the relationship is used in 100% of accesses; otherwise prefer `selectinload()` per query
- Stream large responses via `Response(generator, mimetype=...)` rather than buffering in memory
- Pagination: every list endpoint must paginate (Flask-SQLAlchemy `db.paginate(...)`)

## Error Handling

- Define an app-level base exception (`AppError(Exception)`) with `code` and `status_code` attributes
- Register `@app.errorhandler(AppError)` returning `(jsonify({"error": e.code}), e.status_code)`
- Register `@app.errorhandler(404)`, `@app.errorhandler(500)` for HTML responses
- Services raise domain exceptions (`UserNotFoundError`, `OrderConflictError`); routes translate them to HTTP responses via the registered handlers
- Never return raw stack traces in production responses

## API Design

- Versioning: URL prefix (`/api/v1/...`) — registered as a separate blueprint per version
- JSON: use `flask.jsonify` (sets correct mimetype + serializer) — never `json.dumps` then `Response()`
- Consistent error envelope: `{"error": {"code": "...", "message": "..."}}`
- Pagination: cursor-based for write-heavy lists, offset for stable lists; always include `next`/`prev` in the response
- Rate limit per-route via Flask-Limiter; surface `X-RateLimit-*` headers

## Code Quality

- Functions and methods: max ~40 lines; max 3 nesting levels
- Docstrings on public service methods — explain the WHY (business rule), not the WHAT
- No `print()` in application code — use `app.logger` or `logging.getLogger(__name__)`
- No bare `except:` — always name exception types
- Type-hint service signatures; mypy in CI

## Testing

- pytest + pytest-flask (optional but recommended)
- App fixture creates a fresh `create_app("testing")` per session; client fixture per function
- Each test runs inside a transaction that is rolled back at teardown — never relies on previous state
- See `modules/frameworks/flask/testing/pytest.md` for fixture patterns

## TDD Flow

```
scaffold -> write tests (RED) -> implement (GREEN) -> refactor
```

1. **Scaffold**: blueprint + routes + service stub + form/schema stub
2. **RED**: write failing test through the test client (HTTP-level) or service unit test
3. **GREEN**: implement the minimum code to pass
4. **Refactor**: extract repeated query logic, tighten validators, run lint+mypy — tests must still pass

## Logging and Monitoring

- `app.logger` is a `logging.Logger` configured by Flask — set `LOGGING` config for JSON output in production
- Log levels: ERROR (action needed), WARNING (degraded), INFO (business events), DEBUG (dev only)
- Structured fields: include `request_id` (set in `before_request`), `user_id` (when authenticated), `route`
- Never log secrets, tokens, full request bodies, PII
- Health endpoint: a dedicated blueprint with `/healthz` (liveness, no DB) and `/readyz` (DB + cache + downstream checks)

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated blueprints, schema changes, fixing pre-existing bugs.

## Dos and Don'ts

### Do
- Use `create_app()` application factory — never module-level `app = Flask(__name__)`
- Initialize extensions with `init_app(app)` inside the factory; declare them at module scope
- Put business logic in services, not in routes
- Use Blueprints to group routes by feature; one blueprint per bounded context
- Use SQLAlchemy 2.0 style (`db.session.execute(db.select(Model))`) — `Model.query` is legacy
- Use `selectinload()` / `joinedload()` to prevent N+1 in templates and JSON serializers
- Load `SECRET_KEY` from env vars; rotate to invalidate sessions
- Set `SESSION_COOKIE_SECURE/HTTPONLY/SAMESITE` and `PERMANENT_SESSION_LIFETIME` in production config
- Use `url_for("blueprint.endpoint", ...)` everywhere — never hardcode URLs
- Paginate every list endpoint via `db.paginate(...)`
- CSRF protect every browser form (`{{ form.csrf_token }}`); exempt JSON-only routes that use token auth

### Don't
- Don't run `app.run(debug=True)` in production — the Werkzeug debugger executes arbitrary code
- Don't use `@app.before_first_request` — it was removed in Flask 2.3; run startup work inside `create_app`
- Don't import `Markup` from `flask` — it was removed in Flask 3.0; import from `markupsafe`
- Don't subclass `flask.json.JSONEncoder` — replace `app.json` with a `DefaultJSONProvider` subclass
- Don't put business logic in routes or templates — delegate to services
- Don't string-concat user input into SQL — always use bound parameters with `db.text(...)`
- Don't disable Jinja autoescape globally
- Don't share the same SQLAlchemy session across threads — use `scoped_session` (Flask-SQLAlchemy already does)
- Don't return raw `dict`s from API routes — use `jsonify(...)` to set headers and apply your JSON provider
- Don't use `Model.query.get(id)` — it's legacy; use `db.session.get(Model, id)`
- Don't share secrets across environments — `.env` files for local dev only, never committed
- Don't bypass CSRF on browser-submitted forms; use token auth instead if you need to bypass
