# FastAPI REST — API Protocol Binding

## Integration Setup
- FastAPI is REST-native; no extra package required beyond `fastapi` and `uvicorn[standard]`
- Add `python-multipart` for form data; `httpx` for async test client
- OpenAPI UI auto-available at `/docs` (Swagger) and `/redoc`; disable in production via `docs_url=None`

## Framework-Specific Patterns
- Define path operations with `@app.get/post/put/delete/patch`; group with `APIRouter(prefix="/v1/users", tags=["users"])`
- Request and response models are Pydantic `BaseModel` subclasses; use `response_model=` on the decorator
- Use `Depends()` for dependency injection: database sessions, auth, pagination parameters
- Raise `HTTPException(status_code=..., detail=...)` for client errors; use custom exception handlers via `@app.exception_handler`
- Async handlers: use `async def` for I/O-bound routes; use `def` for CPU-bound (runs in thread pool)
- Path parameters: type-annotated in the function signature; validated automatically by FastAPI
- Query parameters: type-annotated function parameters not in the path become query params automatically

## Scaffolder Patterns
```
app/
  routers/
    users.py               # APIRouter with path operations
  schemas/
    user.py                # Pydantic request/response models
  dependencies/
    auth.py                # Depends() callables
    pagination.py
  exceptions/
    handlers.py            # @app.exception_handler registrations
  main.py                  # FastAPI app, router includes, middleware
```

## Dos
- Use `response_model` to explicitly control serialized output fields; prevents leaking internal fields
- Return meaningful HTTP status codes: `status_code=201` for creation, `204` for deletion
- Use `Query(ge=0, le=100)` and `Path(gt=0)` for built-in validation on query/path params
- Document endpoints with `summary`, `description`, and `responses` in the decorator

## Don'ts
- Don't put database or business logic directly in path operation functions — use service layer
- Don't return raw ORM objects; always pass through a Pydantic `response_model`
- Don't expose `/docs` and `/redoc` in production without authentication
- Don't use synchronous blocking calls inside `async def` handlers
