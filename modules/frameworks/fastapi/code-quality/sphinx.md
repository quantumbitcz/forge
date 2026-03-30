# FastAPI + sphinx

> Extends `modules/code-quality/sphinx.md` with FastAPI-specific integration.
> Generic Sphinx conventions (conf.py setup, CI integration, ReadTheDocs) are NOT repeated here.

## Integration Setup

FastAPI generates OpenAPI JSON automatically — two documentation strategies exist and are often combined:

1. **FastAPI built-in docs** (`/docs` Swagger UI, `/redoc` ReDoc) — runtime interactive docs from OpenAPI spec.
2. **Sphinx autodoc** — developer docs, architecture decisions, and module-level API reference.

```python
# docs/conf.py
extensions = [
    "sphinx.ext.autodoc",
    "sphinx.ext.napoleon",
    "sphinx.ext.viewcode",
    "sphinx.ext.intersphinx",
    "sphinx_autodoc_typehints",
]

# FastAPI modules import without Django setup calls — no special conf.py bootstrap needed
# Mock heavy async dependencies not available at docs build time
autodoc_mock_imports = ["sqlalchemy", "alembic", "redis", "aioboto3"]

intersphinx_mapping = {
    "python": ("https://docs.python.org/3", None),
    "pydantic": ("https://docs.pydantic.dev/latest/", None),
}

autodoc_typehints = "description"
autodoc_typehints_format = "short"
```

## Framework-Specific Patterns

### OpenAPI-to-Sphinx Integration

Export the FastAPI OpenAPI spec as a JSON artifact and reference it from Sphinx:

```python
# scripts/export_openapi.py — run before sphinx-build
import json
from app.main import app

with open("docs/openapi.json", "w") as f:
    json.dump(app.openapi(), f, indent=2)
```

Then embed it in Sphinx docs using `sphinxcontrib-openapi`:

```bash
pip install sphinxcontrib-openapi
```

```python
extensions = ["sphinxcontrib.openapi"]
```

```rst
.. docs/api/openapi.rst
REST API Reference
==================

.. openapi:: ../openapi.json
   :encoding: utf-8
```

### Pydantic Model Autodoc

Pydantic v2 models expose their schema via `model_json_schema()` — document them with autodoc and include field descriptions from `Field(description=...)`:

```python
class UserResponse(BaseModel):
    """API response schema for a user resource."""

    id: int = Field(description="Unique user identifier.")
    email: str = Field(description="Primary email address used for login.")
    display_name: str | None = Field(None, description="Optional public display name.")
```

`sphinx-autodoc-typehints` renders Pydantic field types with their Python types in the generated API docs.

### Documenting Dependency Functions

FastAPI dependency functions are regular Python callables — document them as API contracts:

```python
async def get_current_user(
    token: Annotated[str, Header(alias="Authorization")],
    db: SessionDep,
) -> User:
    """Authenticate the request and return the active user.

    Raises:
        HTTPException(401): If the token is missing or expired.
        HTTPException(403): If the user account is suspended.
    """
```

## Additional Dos

- Export `app.openapi()` as a JSON artifact and reference it from Sphinx via `sphinxcontrib-openapi` — keeps API reference and narrative docs in sync.
- Document Pydantic models with class docstrings and `Field(description=...)` — they appear in both Sphinx output and FastAPI's built-in Swagger UI.
- Add `pydantic` to `intersphinx_mapping` — cross-links to Pydantic's own docs for field validators and config options.

## Additional Don'ts

- Don't replace FastAPI's built-in `/docs` (Swagger UI) with Sphinx for interactive API testing — Swagger UI is superior for endpoint exploration; Sphinx covers narrative and architectural docs.
- Don't autodoc router modules directly using `automodule` on the top-level `app.routers` package without a toctree — it generates a flat list of all routes without logical grouping.
- Don't skip documenting dependency functions — they form the authentication and authorization contract of the API and are as important to document as route handlers.
