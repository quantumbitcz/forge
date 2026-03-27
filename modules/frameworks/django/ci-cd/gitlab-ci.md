# GitLab CI with Django

> Extends `modules/ci-cd/gitlab-ci.md` with Django CI patterns.
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
  DJANGO_SETTINGS_MODULE: config.settings.test
  DATABASE_URL: postgresql://test:test@postgres:5432/test

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
    - uv run mypy .
    - uv run python manage.py check --deploy
  variables:
    SECRET_KEY: ci-dummy-key
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
  script:
    - uv run python manage.py migrate
    - uv run python manage.py makemigrations --check --dry-run
    - uv run pytest --junitxml=report.xml --cov
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

- DO set `DJANGO_SETTINGS_MODULE` as a global variable for all stages
- DO run `makemigrations --check --dry-run` to catch missing migrations
- DO export JUnit XML for GitLab test result integration
- DO use `check --deploy` to validate production security settings

## Additional Don'ts

- DON'T use the production `SECRET_KEY` in CI -- use a dummy value
- DON'T skip the PostgreSQL service for tests that touch the database
- DON'T cache the `.venv/` without also caching uv's dependency cache
