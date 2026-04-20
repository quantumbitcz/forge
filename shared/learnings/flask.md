---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
# Cross-Project Learnings: flask

## PREEMPT items

### FL-PREEMPT-001: N+1 queries via Flask-SQLAlchemy lazy loading in templates and serializers
- **Domain:** persistence
- **Pattern:** Templates that iterate `{% for post in user.posts %}` or JSON serializers that walk `user.profile.organization` trigger one query per row when relationships default to `lazy="select"`. Use `selectinload()` / `joinedload()` in the query building the queryset, or set `lazy="selectin"` on the relationship for always-eager-loaded fields. Detect with `flask-sqlalchemy-debugtoolbar` or `sqlalchemy.event.listen(Engine, "before_cursor_execute", ...)` query counting in tests.
- **Confidence:** HIGH
- **Hit count:** 0

### FL-PREEMPT-002: Module-level `app = Flask(__name__)` blocks per-test isolation
- **Domain:** architecture
- **Pattern:** When `app` is constructed at module import time, every test imports the same instance with the same config and DB. Tests cannot swap to `TestConfig`, cannot use a per-test in-memory SQLite, and the production `SECRET_KEY` ends up in the test environment. Refactor to `create_app(config_name)` and import the factory, not the app, in tests.
- **Confidence:** HIGH
- **Hit count:** 0

### FL-PREEMPT-003: `@csrf.exempt` left on routes that use Flask-Login session auth
- **Domain:** security
- **Pattern:** Developers exempt CSRF temporarily during debugging (e.g. when a JSON-from-fetch flow returns 400) and forget to remove it. Session-cookie-authenticated routes without CSRF protection are vulnerable to cross-site request forgery. Audit rule: `@csrf.exempt` is allowed only on routes that authenticate via `Authorization` header (token auth), never on routes touched by `current_user` (Flask-Login session auth).
- **Confidence:** HIGH
- **Hit count:** 0

### FL-PREEMPT-004: `app.run(debug=True)` shipped to production
- **Domain:** security
- **Pattern:** A `wsgi.py` or `app.py` containing `app.run(debug=True, host="0.0.0.0")` exposes the Werkzeug interactive debugger to anyone who can hit the process. The debugger executes arbitrary Python via the browser. Detect via the L1 regex rule `FL-SEC-001` and via `python -m flask --app wsgi check` in CI. Production deployments must use gunicorn / uWSGI / Waitress; `app.run()` is for local development only.
- **Confidence:** HIGH
- **Hit count:** 0

### FL-PREEMPT-005: `@app.before_request` ordering surprises and short-circuits
- **Domain:** architecture
- **Pattern:** `before_request` handlers run in registration order. A handler that returns a non-`None` value short-circuits the request — subsequent handlers and the route itself are skipped. This is desirable for redirects (e.g. enforce HTTPS) but is a footgun when a logging handler accidentally returns the value of `request.get_json()`. Convention: handlers that may short-circuit should be named `_enforce_*` or `_require_*` and grouped together at the top of `create_app`.
- **Confidence:** MEDIUM
- **Hit count:** 0

### FL-PREEMPT-006: `before_first_request` removed in Flask 2.3 — silent breakage on upgrade
- **Domain:** migration
- **Pattern:** Code using `@app.before_first_request` raises `AttributeError` on Flask 2.3+. Common in projects that ran one-time DB-setup or warm-cache logic this way. Replace by either (a) running the logic inside `create_app` so it's part of construction, or (b) wrapping in `with app.app_context(): ...` and calling from a CLI command (`flask init-db`). The deprecation registry catches this at PREFLIGHT.
- **Confidence:** HIGH
- **Hit count:** 0

### FL-PREEMPT-007: SQLAlchemy session leaks across tests via session-scoped `db` fixture
- **Domain:** testing
- **Pattern:** A pytest fixture that yields `db` at session scope without per-test transaction rollback causes one test's writes to be visible in the next test. Symptoms: tests pass when run in isolation but fail when run together, or vice versa. Use the connection-bound transaction pattern: open a connection, begin a transaction, bind the session to it, yield, then rollback. See `modules/frameworks/flask/testing/pytest.md` for the canonical fixture.
- **Confidence:** HIGH
- **Hit count:** 0

### FL-PREEMPT-008: `Model.query.get(id)` legacy API on Flask-SQLAlchemy 3.x emits LegacyAPIWarning
- **Domain:** migration
- **Pattern:** Flask-SQLAlchemy 3.x deprecates the `Model.query` accessor in favour of the SQLAlchemy 2.0 query builder. Code using `User.query.get(id)`, `User.query.filter_by(...).first()`, `User.query.all()` continues to work but emits warnings and will be removed. Replace with `db.session.get(User, id)` for PK lookups and `db.session.execute(db.select(User).where(...)).scalars().all()` for filtered queries.
- **Confidence:** HIGH
- **Hit count:** 0

### FL-PREEMPT-009: Hardcoded `SECRET_KEY` committed to the repo
- **Domain:** security
- **Pattern:** `app.config["SECRET_KEY"] = "dev"` (or any short literal) in `config.py` or `app/__init__.py` is a common copy-paste from the Flask quickstart. Even when only used in dev, the literal often leaks into production via a shared base config class. Load from `os.environ["SECRET_KEY"]` (which raises `KeyError` early if missing) and rotate to invalidate sessions. Caught by L1 rule `FL-SEC-002`.
- **Confidence:** HIGH
- **Hit count:** 0

### FL-PREEMPT-010: Missing `pool_pre_ping` causes stale-connection 500s after DB failover
- **Domain:** persistence
- **Pattern:** When the DB restarts (planned or failover), idle connections in SQLAlchemy's pool become stale. The next request that picks up a stale connection sees a `psycopg2.OperationalError: server closed the connection unexpectedly`. Set `SQLALCHEMY_ENGINE_OPTIONS = {"pool_pre_ping": True, "pool_recycle": 280}` so SQLAlchemy issues a cheap `SELECT 1` before each checkout and recycles connections older than the load balancer's idle timeout.
- **Confidence:** MEDIUM
- **Hit count:** 0

## Common Pitfalls
<!-- Populated by retrospective agent -->

## Effective Patterns
<!-- Populated by retrospective agent -->
