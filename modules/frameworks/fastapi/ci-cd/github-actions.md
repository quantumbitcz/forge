# GitHub Actions with FastAPI

> Extends `modules/ci-cd/github-actions.md` with FastAPI CI patterns.
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

      - name: Install dependencies
        run: uv sync

      - name: Lint
        run: uv run ruff check .

      - name: Test with coverage
        run: uv run pytest --cov=app --cov-report=xml
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/test
```

## Framework-Specific Patterns

### uv Caching

```yaml
- uses: astral-sh/setup-uv@v4
  with:
    enable-cache: true
    cache-dependency-glob: "uv.lock"
```

The `setup-uv` action caches the uv global cache directory. Use `cache-dependency-glob` for key precision.

### Alembic Migrations in CI

```yaml
- name: Run migrations
  run: uv run alembic upgrade head
  env:
    DATABASE_URL: postgresql://test:test@localhost:5432/test

- name: Verify no pending migrations
  run: |
    uv run alembic check
```

Run migrations before tests to validate schema. `alembic check` fails if model changes lack a migration.

### Docker Image Publishing

```yaml
publish:
  needs: test
  if: github.ref == 'refs/heads/main'
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    - uses: docker/build-push-action@v6
      with:
        context: .
        push: true
        tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

## Scaffolder Patterns

```yaml
patterns:
  workflow: ".github/workflows/ci.yml"
```

## Additional Dos

- DO use `astral-sh/setup-uv` for fast Python dependency management in CI
- DO run `alembic check` to catch missing migrations before merge
- DO use GitHub Actions service containers for PostgreSQL in tests
- DO use GHA cache backend for Docker layer caching

## Additional Don'ts

- DON'T install dependencies with `pip install` when using uv -- use `uv sync`
- DON'T skip the Alembic migration check -- schema drift causes production failures
- DON'T cache `.venv/` manually when using `setup-uv` with `enable-cache: true`
