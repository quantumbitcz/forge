# Django + mutmut

> Extends `modules/code-quality/mutmut.md` with Django-specific integration.
> Generic mutmut conventions (mutation categories, CI caching, kill rate thresholds) are NOT repeated here.

## Integration Setup

Configure mutmut to use Django's test runner via pytest-django and exclude migrations:

```toml
[tool.mutmut]
paths_to_mutate = "apps/"
tests_dir = "tests/unit/"
runner = "python -m pytest -x -q --timeout=15 --no-header -rN"
backup = false
```

**`pyproject.toml` pytest settings (required for runner to work):**
```toml
[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "myproject.settings.test"
```

## Framework-Specific Patterns

### Excluding Migrations

Migrations are auto-generated and contain no business logic worth mutating. Exclude them by scoping `paths_to_mutate` to app subdirectories that exclude the migrations directory:

```toml
[tool.mutmut]
# Mutate domain, services, and views — not migrations or admin registrations
paths_to_mutate = "apps/articles/domain/ apps/articles/services/ apps/accounts/domain/"
tests_dir = "tests/unit/"
runner = "python -m pytest -x -q --timeout=15"
backup = false
```

Alternatively, use a wrapper runner script that explicitly excludes migration paths:

```bash
#!/usr/bin/env bash
# scripts/mutmut-runner.sh
set -e
python -m pytest tests/unit/ -x -q --timeout=15 \
  --ignore=apps/articles/migrations/ \
  2>&1
```

### Django Test Database Setup

mutmut runs tests once per mutant — database setup/teardown happens on every run. Use an in-memory SQLite database in test settings to minimise per-mutant overhead:

```python
# myproject/settings/test.py
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": ":memory:",
        "TEST": {"NAME": ":memory:"},
    }
}
```

### Scoping to Domain Logic

Django projects often mix framework boilerplate with domain logic. Target mutations at the business logic layers:

```toml
[tool.mutmut]
# Target: domain models, service layer, form validation
paths_to_mutate = "apps/*/domain/ apps/*/services/ apps/*/forms.py"
# Skip: views (too integration-heavy), admin (boilerplate), serializers (schema-driven)
```

Views and serializers are better covered by integration tests — mutating them with unit test runners produces many timeouts.

## Additional Dos

- Set `DJANGO_SETTINGS_MODULE` in `[tool.pytest.ini_options]` rather than the mutmut runner command — it is inherited automatically and does not need to be repeated per run.
- Use an in-memory SQLite database in test settings to eliminate database setup time per mutant.
- Scope `paths_to_mutate` to `domain/` and `services/` subdirectories — migrations, `admin.py`, and `apps.py` contain no logic worth mutating.

## Additional Don'ts

- Don't include integration tests or `pytest-django`'s `@pytest.mark.django_db` tests in the mutmut runner — database-backed tests multiply per-mutant runtime significantly; use `--timeout=15` and unit tests only.
- Don't mutate `migrations/` directories — auto-generated code produces noise mutants that will survive because no test exercises them directly.
- Don't run mutmut against the full `apps/` tree without scoping — Django app directories include admin registrations, URL configurations, and AppConfig classes that produce low-signal surviving mutants.
