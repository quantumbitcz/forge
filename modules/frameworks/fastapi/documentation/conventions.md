# FastAPI Documentation Conventions

> Extends `modules/documentation/conventions.md` with FastAPI-specific patterns.

## Code Documentation

- Use Google-style docstrings for all route handlers, service functions, and domain classes.
- Pydantic models: use `Field(description=...)` for every field — FastAPI surfaces these directly in the generated OpenAPI spec.
- Route handlers: docstring becomes the OpenAPI `summary` + `description`. First line = summary. Subsequent lines = description.
- Async functions: note concurrency expectations in the docstring when non-obvious (e.g., CPU-bound tasks that should use `run_in_executor`).

```python
class CreateUserRequest(BaseModel):
    email: EmailStr = Field(description="User's email address. Must be unique.")
    name: str = Field(min_length=1, max_length=100, description="Display name.")

@router.post("/users", response_model=UserResponse, status_code=201)
async def create_user(request: CreateUserRequest, service: UserService = Depends()):
    """Create a new user account.

    Validates uniqueness of the email before persisting. Returns the created
    user with server-assigned ID and timestamps.

    Args:
        request: Validated user creation payload.
        service: Injected user service (see `app/services/user.py`).

    Returns:
        Created user resource with HTTP 201.

    Raises:
        HTTPException(409): If the email is already registered.
    """
```

## Architecture Documentation

- FastAPI auto-generates OpenAPI at `/docs` (Swagger) and `/redoc`. Ensure `app.title`, `app.description`, and `app.version` are set.
- Document the dependency injection graph for non-trivial dependency chains.
- Document async patterns: which operations are truly async (I/O bound) vs synchronous (CPU bound needing executor).
- Pydantic v2 schemas: include a domain model doc for projects with 5+ request/response models.

## Diagram Guidance

- **Request lifecycle:** Sequence diagram showing middleware, dependencies, handler, and response flow.
- **Dependency graph:** Class diagram for complex `Depends()` chains.

## Dos

- `Field(description=...)` on every Pydantic field — it goes straight into the OpenAPI spec
- Set `response_model` on every route — it drives schema generation
- Document `status_code` deviations from default (200) in route docstrings

## Don'ts

- Don't write OpenAPI descriptions that duplicate what the type system already expresses
- Don't skip `app.title`/`app.description` — they appear in the hosted API docs
