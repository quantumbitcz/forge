# CircleCI with Django

> Extends `modules/ci-cd/circleci.md` with Django CI patterns.
> Generic CircleCI conventions (orbs, executors, workspace persistence) are NOT repeated here.

## Integration Setup

```yaml
# .circleci/config.yml
version: 2.1

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
    environment:
      DJANGO_SETTINGS_MODULE: config.settings.test
      DATABASE_URL: postgresql://test:test@localhost:5432/test
    steps:
      - checkout
      - run: pip install uv
      - restore_cache:
          keys:
            - uv-{{ checksum "uv.lock" }}
      - run: uv sync
      - save_cache:
          key: uv-{{ checksum "uv.lock" }}
          paths:
            - .venv
      - run: uv run ruff check .
      - run: uv run python manage.py migrate
      - run: uv run python manage.py makemigrations --check --dry-run
      - run:
          command: uv run pytest --cov --junitxml=report.xml
      - store_test_results:
          path: report.xml

workflows:
  ci:
    jobs:
      - test
```

## Framework-Specific Patterns

### Django System Checks

```yaml
- run:
    name: Django deploy checks
    command: uv run python manage.py check --deploy
    environment:
      DJANGO_SETTINGS_MODULE: config.settings.production
      SECRET_KEY: ci-dummy-key
```

### Static Files Verification

```yaml
- run:
    name: Collect static files
    command: uv run python manage.py collectstatic --noinput
```

### Docker Image Publishing

```yaml
publish:
  executor: python
  steps:
    - checkout
    - setup_remote_docker:
        docker_layer_caching: true
    - run: docker build -t $CIRCLE_PROJECT_REPONAME:$CIRCLE_SHA1 .
    - run: docker push $CIRCLE_PROJECT_REPONAME:$CIRCLE_SHA1
```

## Scaffolder Patterns

```yaml
patterns:
  config: ".circleci/config.yml"
```

## Additional Dos

- DO use secondary service container for PostgreSQL in CircleCI executors
- DO set `DJANGO_SETTINGS_MODULE` in the job environment
- DO run `makemigrations --check --dry-run` to catch missing migrations
- DO use `store_test_results` for CircleCI test insights

## Additional Don'ts

- DON'T use the production `SECRET_KEY` in CI -- use a dummy value for deploy checks
- DON'T skip `collectstatic` verification -- broken static file config causes runtime 500s
- DON'T use `machine` executor for Django tests -- `docker` executor starts faster
