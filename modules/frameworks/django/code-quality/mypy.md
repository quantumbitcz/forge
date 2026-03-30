# Django + mypy

> Extends `modules/code-quality/mypy.md` with Django-specific integration.
> Generic mypy conventions (strict mode, dmypy, CI integration) are NOT repeated here.

## Integration Setup

Install `django-stubs` with the compatible mypy plugin version pinned together:

```bash
pip install django-stubs[compatible-mypy] djangorestframework-stubs
```

```toml
[tool.mypy]
python_version = "3.12"
strict = true
plugins = ["mypy_django_plugin.main"]
exclude = [
    "migrations/",
    ".venv/",
    "build/",
]

[tool.django-stubs]
django_settings_module = "myproject.settings.test"  # use a minimal test settings module

[[tool.mypy.overrides]]
module = "*.migrations.*"
ignore_errors = true

[[tool.mypy.overrides]]
module = "tests.*"
disallow_untyped_defs = false
disallow_any_generics = false
```

## Framework-Specific Patterns

### Model Field Types

`django-stubs` types model fields as descriptors — the plugin resolves them to the correct Python types at access time:

```python
from django.db import models

class Article(models.Model):
    title: models.CharField  # wrong — don't annotate with field class
    title = models.CharField(max_length=200)  # correct — plugin infers str

    # ForeignKey resolved to related model type at access, int at _id attribute
    author = models.ForeignKey("accounts.User", on_delete=models.CASCADE)
    # author → User, author_id → int
```

### QuerySet Generics

Use `QuerySet[MyModel]` and `Manager[MyModel]` for typed queryset return values:

```python
from django.db.models import QuerySet

def get_active_articles() -> QuerySet[Article]:
    return Article.objects.filter(is_published=True)

# Custom manager — annotate with Manager generic
class ArticleManager(models.Manager["Article"]):
    def published(self) -> QuerySet["Article"]:
        return self.filter(is_published=True)
```

### Settings Module for mypy

Use a dedicated minimal settings module that avoids database connections and external service dependencies:

```python
# myproject/settings/mypy.py  (or reuse settings/test.py)
from .base import *

DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": ":memory:"}}
```

Set `django_settings_module = "myproject.settings.mypy"` in `[tool.django-stubs]` — avoids mypy attempting to import production credentials at check time.

## Additional Dos

- Pin `django-stubs` and `mypy` versions together — the plugin ABI is version-coupled; mismatches cause cryptic errors.
- Use `QuerySet[Model]` return types on manager methods — enables type checking of chained queryset operations.
- Add `ignore_errors = true` for `*.migrations.*` — migrations contain dynamic code that mypy cannot type-check meaningfully.

## Additional Don'ts

- Don't annotate model fields with their field class type (`models.CharField`) — annotate the Python type (`str`) only when mypy cannot infer it from the plugin.
- Don't use `# type: ignore` on ORM queryset calls without an error code — the django-stubs plugin resolves most queryset generics; bare ignores hide real type errors.
- Don't run mypy with `DJANGO_SETTINGS_MODULE` pointing to production settings — it may attempt to import secrets, connect to external services, or fail due to missing environment variables.
