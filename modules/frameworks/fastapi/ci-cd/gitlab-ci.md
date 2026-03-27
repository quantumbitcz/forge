# GitLab CI with FastAPI

> Extends `modules/ci-cd/gitlab-ci.md` with FastAPI CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
# .gitlab-ci.yml
image: python:3.12-slim

stages:
  - lint
  - test
  - publish

variables:
  PIP_CACHE_DIR: "$CI_PROJECT_DIR/.cache/pip"
  UV_CACHE_DIR: "$CI_PROJECT_DIR/.cache/uv"

cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths:
    - .cache/uv
    - .venv/

before_script:
  - pip install uv
  - uv sync
```

## Framework-Specific Patterns

### Lint Stage

```yaml
lint:
  stage: lint
  script:
    - uv run ruff check .
    - uv run ruff format --check .
    - uv run mypy app/
```

### Test with PostgreSQL Service

```yaml
test:
  stage: test
  services:
    - postgres:16-alpine
  variables:
    POSTGRES_DB: test
    POSTGRES_USER: test
    POSTGRES_PASSWORD: test
    DATABASE_URL: postgresql://test:test@postgres:5432/test
  script:
    - uv run alembic upgrade head
    - uv run pytest --cov=app --junitxml=report.xml
  artifacts:
    reports:
      junit: report.xml
    expire_in: 1 hour
```

### Docker Image Publishing

```yaml
publish:
  stage: publish
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: ".gitlab-ci.yml"
```

## Additional Dos

- DO use `uv sync` instead of `pip install -r requirements.txt` for reproducible installs
- DO export JUnit XML reports for GitLab test result integration
- DO use `POSTGRES_*` variables matching the service container name (`postgres`)
- DO run Alembic migrations before tests to validate schema

## Additional Don'ts

- DON'T cache `.venv/` without also caching the uv cache -- stale venvs cause conflicts
- DON'T use `pip freeze` for lockfile generation -- use `uv lock`
- DON'T skip `ruff format --check` in CI -- formatting drift accumulates quickly
