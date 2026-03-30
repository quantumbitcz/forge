# Django + coverage-py

> Extends `modules/code-quality/coverage-py.md` with Django-specific integration.
> Generic coverage-py conventions (branch coverage, parallel runs, CI integration) are NOT repeated here.

## Integration Setup

Set `DJANGO_SETTINGS_MODULE` before running coverage and omit auto-generated paths:

```toml
[tool.coverage.run]
source = ["apps", "myproject"]
branch = true
omit = [
    "*/migrations/*",        # auto-generated schema migrations
    "*/management/commands/__init__.py",
    "*/__init__.py",
    "*/settings/*.py",       # configuration — no business logic
    "manage.py",
    "conftest.py",
    "*/wsgi.py",
    "*/asgi.py",
]
parallel = true

[tool.coverage.report]
show_missing = true
skip_empty = true
precision = 2
exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "def __str__",
    "raise NotImplementedError",
    "if TYPE_CHECKING:",
    "if settings.DEBUG",
    "@(abc\\.)?abstractmethod",
]
fail_under = 80

[tool.coverage.html]
directory = "htmlcov"
```

**`pyproject.toml` pytest integration:**
```toml
[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "myproject.settings.test"
addopts = "--cov=apps --cov-report=term-missing --cov-report=xml --cov-fail-under=80"
```

## Framework-Specific Patterns

### Management Command Coverage

Management commands require explicit test invocation via `call_command`:

```python
from django.core.management import call_command
from io import StringIO

def test_my_command_output():
    out = StringIO()
    call_command("my_command", "--dry-run", stdout=out)
    assert "processed" in out.getvalue()
```

Include management command directories in `source` but exclude `__init__.py`:

```toml
[tool.coverage.run]
source = ["apps"]
omit = [
    "*/management/commands/__init__.py",
    # Do NOT omit the command files themselves — they contain business logic
]
```

### Test Settings Module

Use a minimal test settings module that avoids coverage overhead from unused middleware:

```python
# myproject/settings/test.py
from .base import *

DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": ":memory:"}}
EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"
CELERY_TASK_ALWAYS_EAGER = True  # run tasks synchronously in tests
```

### Omitting Migrations Correctly

Use glob patterns that match the auto-generated migration directory at any app depth:

```toml
[tool.coverage.run]
omit = [
    "*/migrations/*.py",  # matches apps/*/migrations/*.py at any depth
]
```

Do not omit the entire `migrations/` directory with `*/migrations/` — coverage.py glob requires the `.py` suffix to match files.

## Additional Dos

- Set `DJANGO_SETTINGS_MODULE` in `[tool.pytest.ini_options]` so coverage inherits it — avoids per-developer environment variable setup.
- Omit `wsgi.py`, `asgi.py`, and `manage.py` — they are deployment entry points with no testable business logic.
- Include management command files in coverage — they often contain complex logic that is undertested.

## Additional Don'ts

- Don't omit entire `apps/*/` directories to raise coverage artificially — improve tests instead.
- Don't set `DJANGO_SETTINGS_MODULE` pointing to production settings in test coverage runs — it may trigger database connections, cache backends, or external service imports at collection time.
- Don't include `settings/` files in coverage `source` — Django settings files are configuration, not code under test; they inflate miss counts.
