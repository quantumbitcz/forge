# Flask + Blueprint Variant

> Blueprint-per-feature layout for Flask 3.x projects. Extends `modules/frameworks/flask/conventions.md`.
> Use this variant when the application is decomposed into a small-to-medium number of bounded contexts
> and you want each context to own its routes, templates, and static assets.

## Layout

```
app/
  __init__.py            # create_app(): registers all blueprints
  extensions.py          # db, login_manager, migrate, csrf module-level singletons
  config.py              # BaseConfig / DevConfig / ProdConfig / TestConfig
  features/
    users/
      __init__.py        # users_bp = Blueprint("users", __name__, url_prefix="/users")
      routes.py          # @users_bp.route(...) handlers
      services.py        # business logic
      models.py          # SQLAlchemy models
      forms.py           # Flask-WTF forms
      schemas.py         # Marshmallow / Pydantic for JSON
      templates/users/   # template_folder='templates' picks this up
      static/users/      # static_folder='static'
    posts/
      ...
    billing/
      ...
```

## Blueprint Construction

```python
# app/features/users/__init__.py
from flask import Blueprint

users_bp = Blueprint(
    "users",
    __name__,
    url_prefix="/users",
    template_folder="templates",
    static_folder="static",
    static_url_path="/users/static",  # avoid clashing with global /static
)

from app.features.users import routes  # noqa: E402,F401
```

`url_prefix` lives at the blueprint, never per-route — keeps routing predictable and refactor-safe.

## Registration Order

Order matters when blueprints share URL space. Register the most-specific prefix first, then the catch-all:

```python
# app/__init__.py inside create_app
from app.features.api import api_bp
from app.features.admin import admin_bp
from app.features.users import users_bp
from app.features.public import public_bp

app.register_blueprint(api_bp, url_prefix="/api/v1")
app.register_blueprint(admin_bp, url_prefix="/admin")
app.register_blueprint(users_bp)        # /users
app.register_blueprint(public_bp)       # / (catch-all, last)
```

`url_for("users.show", user_id=u.id)` resolves regardless of registration order, but error handlers
registered per-blueprint (`@users_bp.errorhandler(...)`) only fire for routes inside that blueprint.

## Template Discovery

Each blueprint's `templates/` folder is scanned in registration order. Convention: namespace template
files by blueprint to prevent collisions across features:

```
templates/
  base.html
  users/
    list.html
    show.html
  posts/
    list.html
```

Reference templates fully qualified: `render_template("users/show.html", user=user)`.

## Static File Scoping

Per-blueprint static files are isolated under their `static_url_path` to avoid clashes:

- `users_bp` static at `/users/static/avatar.png`
- Global static at `/static/main.css`

Reference per-blueprint static via `url_for("users.static", filename="avatar.png")`.

## Nested Blueprints

Discouraged. Flask 2.0+ supports nesting via `parent_bp.register_blueprint(child_bp)`, but it
complicates URL resolution and error-handler scoping. Prefer flat blueprints with clear `url_prefix`.

If absolutely required (e.g. `/api/v1/users` and `/api/v2/users` sharing logic):

```python
api_v1_bp = Blueprint("api_v1", __name__, url_prefix="/api/v1")
users_v1_bp = Blueprint("users_v1", __name__)
api_v1_bp.register_blueprint(users_v1_bp, url_prefix="/users")
app.register_blueprint(api_v1_bp)
# Endpoint: api_v1.users_v1.show
```

## Cross-Blueprint Communication

- Direct model imports across blueprints are discouraged — use service interfaces
- Shared utilities live in `app/common/` (or `app/lib/`) — never inside a feature blueprint
- Cross-feature events: emit blinker signals from services, subscribe in `create_app`

## Error Handlers

```python
# Global, in create_app
@app.errorhandler(404)
def page_not_found(e):
    return render_template("errors/404.html"), 404

# Blueprint-scoped, in app/features/users/routes.py
@users_bp.errorhandler(UserNotFoundError)
def user_not_found(e):
    return jsonify({"error": "user_not_found"}), 404
```

Blueprint handlers only fire for exceptions raised inside that blueprint's routes.

## Dos

- One blueprint per bounded context; flat structure
- `url_prefix=` declared at blueprint construction, never per-route
- Namespace templates and static under the blueprint name to prevent collisions
- Register the most-specific blueprint first, catch-all last
- Use `url_for("blueprint.endpoint", ...)` always — never hardcode URLs
- Co-locate `routes.py`, `services.py`, `models.py`, `forms.py` inside the feature directory
- Register blueprint inside `create_app` — not at import time

## Don'ts

- Don't put business logic inside blueprint route functions — delegate to services
- Don't share a `db.Model` subclass across blueprints' models.py files — define once, import where used
- Don't nest blueprints unless absolutely required (versioned API roots are the rare exception)
- Don't put cross-feature shared utilities inside any blueprint — use `app/common/`
- Don't import from sibling features' `models.py` in routes — go through services
