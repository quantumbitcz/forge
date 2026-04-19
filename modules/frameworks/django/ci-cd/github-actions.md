# GitHub Actions with Django

> Extends `modules/ci-cd/github-actions.md` with Django CI patterns.
> Generic GitHub Actions conventions (workflow triggers, caching strategies, matrix builds) are NOT repeated here.

## Integration Setup

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_DB: test
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U test"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v6
        with:
          python-version: "3.12"

      - name: Install uv
        uses: astral-sh/setup-uv@v4
        with:
          enable-cache: true

      - run: uv sync

      - name: Lint
        run: uv run ruff check .

      - name: Run migrations
        run: uv run python manage.py migrate
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/test

      - name: Collect static files
        run: uv run python manage.py collectstatic --noinput

      - name: Test with coverage
        run: uv run pytest --cov --junitxml=report.xml
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/test
          DJANGO_SETTINGS_MODULE: config.settings.test
```

## Framework-Specific Patterns

### Django Settings Module

```yaml
env:
  DJANGO_SETTINGS_MODULE: config.settings.test
```

Always set `DJANGO_SETTINGS_MODULE` explicitly in CI. Never rely on `DJANGO_SETTINGS_MODULE` defaulting to production settings.

### Migration Check

```yaml
- name: Check for missing migrations
  run: uv run python manage.py makemigrations --check --dry-run
  env:
    DJANGO_SETTINGS_MODULE: config.settings.test
```

`--check --dry-run` fails if model changes lack a migration file. Run this before tests to catch schema drift.

### Django System Check

```yaml
- name: Django system checks
  run: uv run python manage.py check --deploy
  env:
    DJANGO_SETTINGS_MODULE: config.settings.production
    SECRET_KEY: ci-dummy-key
    DATABASE_URL: postgresql://test:test@localhost:5432/test
```

`check --deploy` validates security settings (HTTPS, HSTS, etc.) against the production settings module.

## Scaffolder Patterns

```yaml
patterns:
  workflow: ".github/workflows/ci.yml"
```

## Additional Dos

- DO set `DJANGO_SETTINGS_MODULE` explicitly in every CI job
- DO run `makemigrations --check --dry-run` to catch missing migrations
- DO run `manage.py check --deploy` against production settings
- DO use `collectstatic --noinput` to verify static file configuration

## Additional Don'ts

- DON'T use production `SECRET_KEY` in CI -- use a dummy value for system checks
- DON'T skip the migration check -- schema drift causes production deployment failures
- DON'T run tests against production settings -- use a dedicated `test` settings module
