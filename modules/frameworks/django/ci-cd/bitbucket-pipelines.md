# Bitbucket Pipelines with Django

> Extends `modules/ci-cd/bitbucket-pipelines.md` with Django CI patterns.
> Generic Bitbucket Pipelines conventions (step definitions, deployment environments, pipes) are NOT repeated here.

## Integration Setup

```yaml
# bitbucket-pipelines.yml
image: python:3.12-slim

definitions:
  caches:
    uv: ~/.cache/uv
  services:
    postgres:
      image: postgres:16-alpine
      variables:
        POSTGRES_DB: test
        POSTGRES_USER: test
        POSTGRES_PASSWORD: test

pipelines:
  default:
    - step:
        name: Lint and Test
        caches:
          - uv
        services:
          - postgres
        script:
          - pip install uv && uv sync
          - uv run ruff check .
          - uv run python manage.py migrate
          - uv run python manage.py makemigrations --check --dry-run
          - uv run python manage.py collectstatic --noinput
          - uv run pytest --cov --junitxml=report.xml
        artifacts:
          - report.xml
        environment:
          DJANGO_SETTINGS_MODULE: config.settings.test
          DATABASE_URL: postgresql://test:test@localhost:5432/test
```

## Framework-Specific Patterns

### Parallel Lint and Test

```yaml
- parallel:
    - step:
        name: Lint
        caches:
          - uv
        script:
          - pip install uv && uv sync
          - uv run ruff check .
          - uv run python manage.py check --deploy
        environment:
          DJANGO_SETTINGS_MODULE: config.settings.production
          SECRET_KEY: ci-dummy-key
    - step:
        name: Test
        caches:
          - uv
        services:
          - postgres
        script:
          - pip install uv && uv sync
          - uv run python manage.py migrate
          - uv run pytest --cov --junitxml=report.xml
        environment:
          DJANGO_SETTINGS_MODULE: config.settings.test
          DATABASE_URL: postgresql://test:test@localhost:5432/test
```

### Docker Image Publishing

```yaml
pipelines:
  branches:
    main:
      - step:
          name: Build and Push Image
          services:
            - docker
          script:
            - docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD
            - docker build -t $DOCKER_REGISTRY/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT .
            - docker push $DOCKER_REGISTRY/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: "bitbucket-pipelines.yml"
```

## Additional Dos

- DO define a custom `uv` cache for dependency caching
- DO use `parallel` steps for independent lint and test jobs
- DO set `DJANGO_SETTINGS_MODULE` per step as needed
- DO run `makemigrations --check --dry-run` before tests

## Additional Don'ts

- DON'T forget `services: [postgres]` declaration for database tests
- DON'T use production `SECRET_KEY` in CI -- use a dummy value for deploy checks
- DON'T skip `collectstatic` verification before publishing Docker images
