# Django + Python Variant

> Python 3.10+ patterns for Django projects. Extends `modules/languages/python.md` and `modules/frameworks/django/conventions.md`. Applies when Python >= 3.10.

## Type Hints with Django Stubs

- Install `django-stubs` and `djangorestframework-stubs` for mypy support
- Configure `mypy.ini` or `pyproject.toml`:
  ```toml
  [tool.mypy]
  plugins = ["mypy_django_plugin.main", "mypy_drf_plugin.main"]

  [tool.django-stubs]
  django_settings_module = "config.settings"
  ```
- Type-annotate all service function signatures, including queryset return types:
  ```python
  from django.db.models import QuerySet

  def get_active_users() -> QuerySet["User"]:
      return User.objects.filter(is_active=True)
  ```
- Use `TYPE_CHECKING` guard for model imports that would cause circular import:
  ```python
  from __future__ import annotations
  from typing import TYPE_CHECKING
  if TYPE_CHECKING:
      from myapp.models import User
  ```

## Pydantic Integration with DRF

- Optional: use Pydantic for service-layer validation (not HTTP layer — DRF handles that)
- Use `pydantic.BaseModel` for internal service contracts and complex parameter objects
- Do not use Pydantic models as DRF serializers — they serve different layers

## Modern Python Patterns

- Use `X | None` syntax (3.10+) instead of `Optional[X]` in type hints
- Use builtin `dict`, `list`, `tuple` (3.9+) instead of `typing.Dict`, `typing.List`
- Use `dataclasses.dataclass(frozen=True)` for immutable value objects passed between layers
- Use `from __future__ import annotations` in all modules for forward reference support

## Django-Specific Python Idioms

- Use `__class_getitem__` generics for typed custom managers:
  ```python
  class ActiveManager(models.Manager["User"]):
      def get_queryset(self) -> QuerySet["User"]:
          return super().get_queryset().filter(is_active=True)
  ```
- Enum for model choices (Django 3.0+):
  ```python
  class Status(models.TextChoices):
      PENDING = "pending", "Pending"
      ACTIVE = "active", "Active"
  ```
  Use `Status.choices` in the field definition; type-hint as `str` (TextChoices values are strings)
- `pathlib.Path` for settings file paths: `BASE_DIR = Path(__file__).resolve().parent.parent`

## Async Views

- Django supports `async def` views natively (Django 4.1+ for ORM async)
- Use `sync_to_async` to call synchronous ORM methods in async views when needed:
  ```python
  from asgiou.sync import sync_to_async
  users = await sync_to_async(list)(User.objects.filter(is_active=True))
  ```
- Prefer synchronous views unless there is a compelling async I/O reason — Django's WSGI stack is synchronous by default

## Dependency and Tooling

- Use `uv` or `poetry` for dependency management
- Pin dependencies in `pyproject.toml`
- Use `ruff` for linting and formatting (replaces `flake8` + `black`)
- Use `mypy` with `django-stubs` for type checking — run in CI
- Environment management: `python-decouple` or `django-environ` for reading `.env` files

## Match Statements (Python 3.10+, PEP 634)

Use `match` for complex dispatch (view branching, serializer selection). Prefer match over if/elif chains for 3+ branches with pattern matching:

```python
match request.method:
    case "GET":
        return self.list(request)
    case "POST":
        return self.create(request)
    case _:
        return HttpResponseNotAllowed(["GET", "POST"])
```

## Django 5.0+ Features

- Use `GeneratedField` for computed database columns
- Use `Field.db_default` for database-level defaults
- Use facet filters in admin

```python
from django.db.models import GeneratedField, F, Value
from django.db.models.functions import Concat

class UserProfile(models.Model):
    first_name = models.CharField(max_length=100)
    last_name = models.CharField(max_length=100)
    full_name = GeneratedField(
        expression=Concat(F("first_name"), Value(" "), F("last_name")),
        output_field=models.CharField(max_length=201),
        db_persist=True,
    )
```
