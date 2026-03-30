# FastAPI + ruff

> Extends `modules/code-quality/ruff.md` with FastAPI-specific integration.
> Generic ruff conventions (rule categories, CI integration, pre-commit setup) are NOT repeated here.

## Integration Setup

```toml
[tool.ruff]
target-version = "py312"
line-length = 100
exclude = [".venv", "__pycache__", "*.egg-info", "dist"]

[tool.ruff.lint]
select = [
    "E", "W", "F", "I", "N", "UP", "B", "C4", "S", "ANN", "D", "RUF",
    "ASYNC",  # flake8-async — async/await correctness
    "TCH",    # flake8-type-checking — TYPE_CHECKING guard usage
]
ignore = [
    "D100", "D104",
    "ANN101",
    "S101",
    "B008",   # do not perform function calls in default argument — conflicts with Depends()
]

[tool.ruff.lint.per-file-ignores]
"app/routers/**/*.py" = [
    "ANN201",  # missing return type — FastAPI infers response model from return annotation
]
"tests/**/*.py" = ["S101", "ANN", "D", "ASYNC"]
"app/main.py" = ["ANN"]
```

## Framework-Specific Patterns

### Pydantic Model Rules

Pydantic v2 models benefit from specific ruff rules:

```toml
[tool.ruff.lint]
select = [
    # ... base rules ...
    "PYI",   # flake8-pyi — type stub patterns (useful for Pydantic field types)
]
```

Key rules for Pydantic models:

| Rule | What It Catches |
|---|---|
| `B006` | Mutable default argument — applies to `model_fields` with mutable defaults |
| `UP006`/`UP007` | Use `list` / `X \| None` instead of `List` / `Optional[X]` in field types |
| `RUF012` | Mutable class variable without `ClassVar` — Pydantic fields vs class attributes |

### `B008` Suppression for Dependency Injection

FastAPI's `Depends()`, `Query()`, `Header()`, and `Body()` are function calls in default argument position — ruff `B008` flags this pattern. Suppress `B008` globally for FastAPI projects:

```toml
[tool.ruff.lint]
ignore = [
    "B008",  # FastAPI Depends()/Query()/Header() in default arguments — idiomatic pattern
]
```

### Async Function Rules

The `ASYNC` rule set catches common async mistakes in FastAPI handlers:

| Rule | What It Catches |
|---|---|
| `ASYNC100` | `async def` with no `await` — unnecessary async annotation |
| `ASYNC101` | `open()` inside async function — use `anyio.open_file()` instead |
| `ASYNC102` | `os.path` calls inside async function — use `anyio.Path` instead |

### Router `per-file-ignores`

FastAPI routers often omit explicit return type annotations because the framework infers them from `response_model`. Suppress `ANN201` (missing return type) for router files without suppressing it globally:

```toml
[tool.ruff.lint.per-file-ignores]
"app/routers/**/*.py" = ["ANN201"]
"app/api/v*/**/*.py" = ["ANN201"]
```

## Additional Dos

- Enable `ASYNC` rules — FastAPI handlers mix sync and async code; `ASYNC100` catches accidental `async def` without `await` that adds overhead without benefit.
- Enable `TCH` rules to move type-only imports under `TYPE_CHECKING` — reduces import overhead on FastAPI startup.
- Enable `B008` suppression globally for FastAPI — the `Depends()` pattern is idiomatic and documented; flagging it produces only noise.

## Additional Don'ts

- Don't suppress `ANN` globally — annotate Pydantic models and service layer functions; only suppress on router files where FastAPI infers types from `response_model`.
- Don't disable `RUF012` — it distinguishes Pydantic model fields from plain class variables; mutable class variables in Pydantic models cause unexpected shared state between instances.
- Don't ignore `ASYNC101`/`ASYNC102` without replacing blocking I/O calls — synchronous `open()` and `os.path` inside async handlers block the event loop.
