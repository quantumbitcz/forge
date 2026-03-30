# FastAPI + mypy

> Extends `modules/code-quality/mypy.md` with FastAPI-specific integration.
> Generic mypy conventions (strict mode, dmypy, CI integration) are NOT repeated here.

## Integration Setup

Install the Pydantic mypy plugin alongside FastAPI stubs:

```bash
pip install pydantic[mypy]
# FastAPI does not require separate stubs — it ships with py.typed marker
```

```toml
[tool.mypy]
python_version = "3.12"
strict = true
plugins = ["pydantic.mypy"]

[[tool.mypy.overrides]]
module = "tests.*"
disallow_untyped_defs = false
disallow_any_generics = false
```

**Pydantic plugin configuration:**
```toml
[tool.pydantic-mypy]
init_forbid_extra = true
init_typed = true
warn_required_dynamic_aliases = true
```

## Framework-Specific Patterns

### Pydantic v2 Model Config Typing

Use `model_config = ConfigDict(...)` with typed fields — the Pydantic mypy plugin validates config options:

```python
from pydantic import BaseModel, ConfigDict

class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True, populate_by_name=True)

    id: int
    email: str
    display_name: str | None = None
```

Do not use the deprecated class-based `class Config` syntax — mypy cannot fully type-check it and it is removed in Pydantic v3.

### Dependency Injection Function Types

FastAPI's `Depends()` resolves at runtime — annotate dependency functions with explicit return types so mypy can check injection sites:

```python
from typing import Annotated
from fastapi import Depends

async def get_db_session() -> AsyncSession:  # explicit return type
    async with session_factory() as session:
        yield session

SessionDep = Annotated[AsyncSession, Depends(get_db_session)]

async def create_user(
    data: UserCreateRequest,
    db: SessionDep,  # mypy resolves to AsyncSession
) -> UserResponse:
    ...
```

### Response Model Typing

Type router handler return values explicitly — FastAPI infers `response_model` from the return annotation, and mypy validates it:

```python
from fastapi import APIRouter

router = APIRouter()

@router.get("/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: int, db: SessionDep) -> UserResponse:
    # mypy checks that the return type matches response_model
    user = await db.get(User, user_id)
    return UserResponse.model_validate(user)
```

### Annotated DI with `Annotated`

Use `Annotated` for dependency injection instead of bare `= Depends(...)` — `Annotated` form is fully typed and works with mypy strict mode:

```python
from typing import Annotated
from fastapi import Depends, Header

CurrentUser = Annotated[User, Depends(get_current_user)]
AuthToken = Annotated[str, Header(alias="Authorization")]
```

## Additional Dos

- Enable `pydantic.mypy` plugin — it resolves `model_fields`, validators, and `model_validate()` return types that are opaque without it.
- Use `Annotated[T, Depends(...)]` for dependency types — mypy resolves `Annotated` metadata at check time, enabling type inference at injection sites.
- Set `init_forbid_extra = true` in `[tool.pydantic-mypy]` — catches extra field assignments not declared in the model.

## Additional Don'ts

- Don't use `# type: ignore` on Pydantic model constructors — install the plugin instead; most apparent type errors on `BaseModel` subclasses are resolved by the Pydantic mypy plugin.
- Don't annotate FastAPI path operation functions with `-> Any` to silence return-type mismatches — annotate the correct `response_model` type and let mypy verify the contract.
- Don't use `Optional[T]` in Pydantic v2 models — use `T | None`; Pydantic v2's `model_config` treats them the same at runtime but `Optional` generates spurious mypy warnings in strict mode.
