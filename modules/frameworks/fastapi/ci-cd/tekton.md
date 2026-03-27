# Tekton with FastAPI

> Extends `modules/ci-cd/tekton.md` with FastAPI pipeline task patterns.
> Generic Tekton conventions (Tasks, Pipelines, PipelineRuns, workspaces) are NOT repeated here.

## Integration Setup

```yaml
# tekton/tasks/fastapi-test.yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: fastapi-test
spec:
  workspaces:
    - name: source
    - name: uv-cache
      optional: true
  params:
    - name: PYTHON_IMAGE
      default: python:3.12-slim
  steps:
    - name: install-and-test
      image: $(params.PYTHON_IMAGE)
      workingDir: $(workspaces.source.path)
      env:
        - name: UV_CACHE_DIR
          value: $(workspaces.uv-cache.path)
      script: |
        #!/usr/bin/env bash
        pip install uv
        uv sync
        uv run ruff check .
        uv run pytest --junitxml=report.xml --cov=app
```

## Framework-Specific Patterns

### Database Sidecar for Tests

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: fastapi-integration-test
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
      script: |
        #!/usr/bin/env bash
        pip install uv && uv sync
        # Wait for PostgreSQL
        until pg_isready -h localhost -U test 2>/dev/null; do sleep 1; done
        uv run alembic upgrade head
        uv run pytest tests/integration/ --junitxml=report.xml
```

### Kaniko Image Build

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: fastapi-kaniko-build
spec:
  workspaces:
    - name: source
    - name: docker-config
  params:
    - name: IMAGE
    - name: TAG
      default: latest
  steps:
    - name: kaniko
      image: gcr.io/kaniko-project/executor:latest
      args:
        - --dockerfile=$(workspaces.source.path)/Dockerfile
        - --context=$(workspaces.source.path)
        - --destination=$(params.IMAGE):$(params.TAG)
```

### Full Pipeline

```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: fastapi-ci
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
    - name: lint-and-test
      taskRef:
        name: fastapi-test
      runAfter: [fetch-source]
      workspaces:
        - name: source
          workspace: shared-workspace
        - name: uv-cache
          workspace: uv-cache
    - name: build-image
      taskRef:
        name: fastapi-kaniko-build
      runAfter: [lint-and-test]
      workspaces:
        - name: source
          workspace: shared-workspace
```

## Scaffolder Patterns

```yaml
patterns:
  task_test: "tekton/tasks/fastapi-test.yaml"
  task_integration: "tekton/tasks/fastapi-integration-test.yaml"
  task_image: "tekton/tasks/fastapi-kaniko-build.yaml"
  pipeline: "tekton/pipelines/fastapi-ci.yaml"
```

## Additional Dos

- DO use sidecars for PostgreSQL rather than external service dependencies
- DO persist uv cache via workspaces backed by PersistentVolumeClaims
- DO wait for PostgreSQL readiness before running Alembic migrations
- DO use Kaniko for rootless image builds

## Additional Don'ts

- DON'T skip `runAfter` ordering -- Tekton tasks run in parallel by default
- DON'T embed registry credentials in Task specs -- use Tekton's `docker-config` workspace
- DON'T install uv globally in the image -- install per-step to keep tasks portable
