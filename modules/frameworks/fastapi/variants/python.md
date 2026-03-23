# FastAPI + Python Variant

> Python-specific patterns for FastAPI projects. Extends `modules/languages/python.md` and `modules/frameworks/fastapi/conventions.md`.

## Async Anti-Patterns

- **Blocking the event loop:** `open()`, `os.path.exists()`, `requests.get()` are all blocking. Use `aiofiles`, `asyncio.to_thread()`, `httpx.AsyncClient`
- **CPU-bound in async:** Don't do heavy computation in async handlers -- offload to `asyncio.to_thread()` or a background worker
- **Missing await:** Forgetting `await` on a coroutine silently returns a coroutine object instead of the result

## Type Hints

- Type hints on ALL function signatures and return types
- Use `X | None` syntax (3.10+) instead of `Optional[X]`
- Use builtin `dict`, `list`, `tuple` (3.9+) instead of `typing.Dict`, `typing.List`
- Use `AsyncGenerator[T, None]` for async generator type hints

## Pydantic Patterns

- Use `model_config = ConfigDict(...)` instead of inner `class Config:`
- Use `field_validator` instead of `validator` (Pydantic v2)
- Use `model_validator(mode='before')` for pre-validation transforms
- Use `@computed_field` for derived properties on models

## Lifespan Events

- Use lifespan context manager instead of deprecated `@app.on_event("startup")`
- Initialize DB pools, caches, and external connections in lifespan

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    # startup
    await init_db()
    yield
    # shutdown
    await close_db()
```

## Structured Logging

- Use `structlog` for structured JSON logging
- Include request_id, user_id, operation in log context
- Never use `print()` -- use `logger.info()`, `logger.error()` etc.

## Dependency Management

- Use `uv` or `poetry` for dependency management
- Pin dependencies in `pyproject.toml`
- Use `ruff` for linting and formatting (replaces `flake8` + `black`)
