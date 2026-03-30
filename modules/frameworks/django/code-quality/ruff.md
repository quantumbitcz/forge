# Django + ruff

> Extends `modules/code-quality/ruff.md` with Django-specific integration.
> Generic ruff conventions (rule categories, CI integration, pre-commit setup) are NOT repeated here.

## Integration Setup

Add the `DJ` (flake8-django) rule set and configure migration exclusions:

```toml
[tool.ruff.lint]
select = [
    "E", "W", "F", "I", "N", "UP", "B", "C4", "S", "ANN", "D", "RUF",
    "DJ",   # flake8-django — Django-specific checks
]
ignore = [
    "D100", "D104",
    "ANN101",
    "S101",
    "DJ001",  # avoid-nullable-model-field-with-null-true — project-level decision
]

[tool.ruff.lint.per-file-ignores]
"*/migrations/*.py" = [
    "E501",    # auto-generated lines may exceed line length
    "N806",    # variable in function should be lowercase (migration classes)
    "DJ",      # all Django rules — migrations are auto-generated
    "ANN",     # no type annotations in migrations
    "D",       # no docstrings in migrations
]
"*/settings/*.py" = [
    "F405",   # may be undefined or from star import (settings may use wildcard)
    "F403",   # unable to detect undefined names from star import
    "S105",   # hardcoded password (settings files show dummy values in examples)
]
"*/settings/test.py" = ["S105", "S106"]
"manage.py" = ["ANN"]
"*/tests/**/*.py" = ["S101", "ANN", "D", "DJ"]
```

## Framework-Specific Patterns

### DJ Rule Category

Key `DJ` rules enabled by the flake8-django plugin:

| Rule | What It Catches |
|---|---|
| `DJ001` | `null=True` on string fields (`CharField`, `TextField`) — use `blank=True` instead |
| `DJ006` | Do not use `exclude` with `ModelForm` — prefer explicit `fields` |
| `DJ007` | Do not use `__all__` with `ModelForm` — prefer explicit `fields` |
| `DJ008` | Model does not define `__str__` method |
| `DJ012` | Order of model inner classes and standard methods does not follow Django style guide |

### Settings Module Exclusions

Django settings files often use wildcard imports (`from base import *`) for environment layering. The `F403`/`F405` suppression in `per-file-ignores` handles this without disabling import checking globally.

```toml
[tool.ruff.lint.per-file-ignores]
"*/settings/production.py" = ["F405", "F403"]
"*/settings/staging.py" = ["F405", "F403"]
```

### Migration Safety

Never run `ruff check --fix` on migrations — auto-fixes on auto-generated code can silently break the migration graph. Lint migrations read-only:

```yaml
# .github/workflows/quality.yml
- name: Ruff check migrations (read-only)
  run: ruff check apps/*/migrations/ --no-fix
```

## Additional Dos

- Enable `DJ` rules from project start — `DJ008` (missing `__str__`) and `DJ012` (method ordering) catch structural issues early.
- Add `*/migrations/*.py` to `per-file-ignores` for `DJ` rules — Django auto-generated migrations legitimately violate many checks.
- Pin the `flake8-django` plugin version alongside ruff — `DJ` rule availability depends on ruff's bundled plugin version.

## Additional Don'ts

- Don't suppress `DJ001` globally without a documented reason — nullable string fields cause subtle query bugs (`""` vs `None` dual-null state).
- Don't add `manage.py` to the global `exclude` — it should still be checked for import and security patterns; suppress only `ANN` annotations.
- Don't run `ruff format --fix` on migration files automatically in CI — formatting changes can alter migration file hashes and cause Django to detect spurious migration changes.
