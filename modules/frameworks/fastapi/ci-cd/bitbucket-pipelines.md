# Bitbucket Pipelines with FastAPI

> Extends `modules/ci-cd/bitbucket-pipelines.md` with FastAPI CI patterns.
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
          - pip install uv
          - uv sync
          - uv run ruff check .
          - uv run alembic upgrade head
          - uv run pytest --cov=app --junitxml=report.xml
        artifacts:
          - report.xml
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
          - uv run ruff format --check .
    - step:
        name: Test
        caches:
          - uv
        services:
          - postgres
        script:
          - pip install uv && uv sync
          - uv run alembic upgrade head
          - uv run pytest --cov=app --junitxml=report.xml
        environment:
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

- DO define a custom `uv` cache pointing to `~/.cache/uv`
- DO use `parallel` steps for independent lint and test jobs
- DO declare PostgreSQL as a service for integration tests
- DO run Alembic migrations before test execution

## Additional Don'ts

- DON'T forget `services: [postgres]` declaration -- database tests fail silently without it
- DON'T cache `.venv/` across branches -- use `uv sync` with uv cache instead
- DON'T exceed the 2GB artifact limit -- export only test reports, not coverage HTML
