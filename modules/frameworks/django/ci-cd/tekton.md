# Tekton with Django

> Extends `modules/ci-cd/tekton.md` with Django pipeline task patterns.
> Generic Tekton conventions (Tasks, Pipelines, PipelineRuns, workspaces) are NOT repeated here.

## Integration Setup

```yaml
# tekton/tasks/django-test.yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: django-test
spec:
  workspaces:
    - name: source
    - name: uv-cache
      optional: true
  params:
    - name: PYTHON_IMAGE
      default: python:3.12-slim
    - name: SETTINGS_MODULE
      default: config.settings.test
  steps:
    - name: install-and-test
      image: $(params.PYTHON_IMAGE)
      workingDir: $(workspaces.source.path)
      env:
        - name: DJANGO_SETTINGS_MODULE
          value: $(params.SETTINGS_MODULE)
        - name: UV_CACHE_DIR
          value: $(workspaces.uv-cache.path)
      script: |
        #!/usr/bin/env bash
        pip install uv
        uv sync
        uv run ruff check .
        uv run python manage.py migrate
        uv run python manage.py makemigrations --check --dry-run
        uv run pytest --junitxml=report.xml --cov
```

## Framework-Specific Patterns

### Database Sidecar for Tests

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: django-integration-test
spec:
  workspaces:
    - name: source
  sidecars:
    - name: postgres
      image: postgres:16-alpine
      env:
        - name: POSTGRES_DB
          value: test
        - name: POSTGRES_USER
          value: test
        - name: POSTGRES_PASSWORD
          value: test
  steps:
    - name: test
      image: python:3.12-slim
      workingDir: $(workspaces.source.path)
      env:
        - name: DATABASE_URL
          value: postgresql://test:test@localhost:5432/test
        - name: DJANGO_SETTINGS_MODULE
          value: config.settings.test
      script: |
        #!/usr/bin/env bash
        pip install uv && uv sync
        until pg_isready -h localhost -U test 2>/dev/null; do sleep 1; done
        uv run python manage.py migrate
        uv run python manage.py collectstatic --noinput
        uv run pytest --junitxml=report.xml
```

### Full Pipeline

```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: django-ci
spec:
  workspaces:
    - name: shared-workspace
    - name: uv-cache
  tasks:
    - name: fetch-source
      taskRef:
        name: git-clone
      workspaces:
        - name: output
          workspace: shared-workspace
    - name: test
      taskRef:
        name: django-integration-test
      runAfter: [fetch-source]
      workspaces:
        - name: source
          workspace: shared-workspace
    - name: build-image
      taskRef:
        name: kaniko-build
      runAfter: [test]
      workspaces:
        - name: source
          workspace: shared-workspace
```

## Scaffolder Patterns

```yaml
patterns:
  task_test: "tekton/tasks/django-test.yaml"
  task_integration: "tekton/tasks/django-integration-test.yaml"
  pipeline: "tekton/pipelines/django-ci.yaml"
```

## Additional Dos

- DO use sidecars for PostgreSQL rather than external service dependencies
- DO set `DJANGO_SETTINGS_MODULE` in step environment variables
- DO wait for PostgreSQL readiness before running migrations
- DO run `collectstatic` before tests to verify static file configuration

## Additional Don'ts

- DON'T skip `runAfter` ordering -- Tekton tasks run in parallel by default
- DON'T embed database credentials in Task specs -- use Tekton secrets
- DON'T use production settings module in test tasks
