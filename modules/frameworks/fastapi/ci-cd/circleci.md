# CircleCI with FastAPI

> Extends `modules/ci-cd/circleci.md` with FastAPI CI patterns.
> Generic CircleCI conventions (orbs, executors, workspace persistence) are NOT repeated here.

## Integration Setup

```yaml
# .circleci/config.yml
version: 2.1

orbs:
  python: circleci/python@2.1
  docker: circleci/docker@2.6

executors:
  python:
    docker:
      - image: cimg/python:3.12
      - image: cimg/postgres:16.0
        environment:
          POSTGRES_DB: test
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test

jobs:
  test:
    executor: python
    steps:
      - checkout
      - run:
          name: Install uv
          command: pip install uv
      - restore_cache:
          keys:
            - uv-{{ checksum "uv.lock" }}
      - run: uv sync
      - save_cache:
          key: uv-{{ checksum "uv.lock" }}
          paths:
            - .venv
      - run: uv run ruff check .
      - run:
          command: uv run pytest --cov=app --junitxml=report.xml
          environment:
            DATABASE_URL: postgresql://test:test@localhost:5432/test
      - store_test_results:
          path: report.xml

workflows:
  ci:
    jobs:
      - test
```

## Framework-Specific Patterns

### uv Cache Strategy

```yaml
- restore_cache:
    keys:
      - uv-{{ checksum "uv.lock" }}
      - uv-
- run: uv sync
- save_cache:
    key: uv-{{ checksum "uv.lock" }}
    paths:
      - .venv
      - ~/.cache/uv
```

### Alembic Migration Check

```yaml
- run:
    name: Run migrations
    command: uv run alembic upgrade head
    environment:
      DATABASE_URL: postgresql://test:test@localhost:5432/test
- run:
    name: Check no pending migrations
    command: uv run alembic check
```

### Docker Image Publishing

```yaml
publish:
  executor: python
  steps:
    - checkout
    - setup_remote_docker:
        docker_layer_caching: true
    - docker/build:
        image: $CIRCLE_PROJECT_REPONAME
        tag: $CIRCLE_SHA1
    - docker/push:
        image: $CIRCLE_PROJECT_REPONAME
        tag: $CIRCLE_SHA1
```

## Scaffolder Patterns

```yaml
patterns:
  config: ".circleci/config.yml"
```

## Additional Dos

- DO use secondary service container for PostgreSQL in CircleCI executors
- DO cache both `.venv` and `~/.cache/uv` keyed by `uv.lock` checksum
- DO use `store_test_results` for CircleCI test insights integration
- DO run `alembic check` to catch unapplied migrations

## Additional Don'ts

- DON'T use `machine` executor for simple Python builds -- `docker` executor starts faster
- DON'T skip `setup_remote_docker` for steps that build Docker images
- DON'T cache the entire project directory -- cache only dependency directories
